#!/usr/bin/env python3
"""Publish the rooted LG C1's telemetry to MQTT for Home Assistant.

Pulls rather than pushes: t1 runs /home/root/tv-stats on the TV over ssh with a
key bound to that script by command= in authorized_keys. Nothing runs on the TV
between polls, no broker credentials sit on a rooted set, and the broker stays
off the LAN.

A failed poll is two different things. A TV that is off the network is normal
and marks the device unavailable. A TV that answers but refuses the key or
returns something other than tv-stats output means root, or the key, is gone -
the usual cause is a firmware update - and raises root_problem.
"""

import json
import os
import re
import signal
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone

import paho.mqtt.client as mqtt

MQTT_HOST = os.environ.get("MQTT_HOST", "127.0.0.1")
MQTT_PORT = int(os.environ.get("MQTT_PORT", "1883"))
MQTT_USER = os.environ.get("MQTT_USER", "tv")
MQTT_PASS = os.environ.get("MQTT_PASS", "")
TV_HOST = os.environ.get("TV_HOST", "192.168.8.141")
NODE = os.environ.get("NODE_NAME", "lg_c1")

INTERVAL = int(os.environ.get("INTERVAL", "30"))
FULL_EVERY = int(os.environ.get("FULL_EVERY", "10"))

CRED = os.environ.get("CREDENTIALS_DIRECTORY", "/etc/tv-metrics")

STATE_TOPIC = f"{NODE}/metrics/state"
AVAIL_TOPIC = f"{NODE}/metrics/availability"
DISCOVERY_TOPIC = f"homeassistant/device/{NODE}/config"

OFFLINE_MARKERS = ("timed out", "no route to host", "connection refused",
                   "host is down", "network is unreachable",
                   "connection closed", "connection reset")

DYNAMIC_RANGE = {"sdr": "SDR", "hdr": "HDR10", "hlg": "HLG",
                 "dolbyHdr": "Dolby Vision", "technicolorHdr": "Technicolor HDR"}


def log(msg):
    print(msg, file=sys.stderr, flush=True)


# One connection per poll, deliberately not multiplexed: a held-open master
# with keepalives could stop the TV dropping off the network in standby.
def ssh(mode):
    cmd = [
        "ssh", "-T",
        "-i", f"{CRED}/id_ed25519",
        "-o", f"UserKnownHostsFile={CRED}/known_hosts",
        "-o", "GlobalKnownHostsFile=/dev/null",
        "-o", "StrictHostKeyChecking=yes",
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=5",
        f"root@{TV_HOST}", mode,
    ]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=20,
                           stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return "offline", None
    if p.returncode == 255:
        err = p.stderr.lower()
        if any(m in err for m in OFFLINE_MARKERS):
            return "offline", None
        log(f"ssh refused: {p.stderr.strip()[-200:]}")
        return "problem", None
    try:
        data = json.loads(p.stdout)
    except json.JSONDecodeError:
        log(f"not tv-stats output (rc {p.returncode}): {p.stdout[:120]!r}")
        return "problem", None
    if data.get("mode") != mode:
        return "problem", None
    return "ok", data


def num(text, cast=float):
    try:
        return cast(str(text).split()[0])
    except (ValueError, IndexError, TypeError):
        return None


def luna(data, key):
    v = data.get(key)
    return v if isinstance(v, dict) and v.get("returnValue") else {}


def cpu_times(text):
    """(busy, idle, every counter used) from /proc/stat's aggregate cpu line."""
    parts = str(text or "").split()
    if len(parts) < 9 or parts[0] != "cpu":
        return None
    try:
        user, nice, system, idle, iowait, irq, softirq, steal = map(int, parts[1:9])
    except ValueError:
        return None
    counters = (user, nice, system, idle, iowait, irq, softirq, steal)
    return user + nice + system + irq + softirq + steal, idle + iowait, counters


class Reader:
    def __init__(self):
        self.booted_at = None
        self.slow = {}
        self.stat = None

    def reset(self):
        # After a gap the next delta would be an average over the whole gap.
        self.stat = None

    def cpu_utilisation(self, text):
        # Not /proc/lg/pm/current_load: that is the power manager's per-sample
        # frequency hint and swings 0/100 from one second to the next.
        cur, prev = cpu_times(text), self.stat
        self.stat = cur
        if cur is None or prev is None:
            return None
        # LG hot-plugs cores, so counters can go backwards between polls.
        if any(c < p for c, p in zip(cur[2], prev[2])):
            return None
        dbusy, dtotal = cur[0] - prev[0], (cur[0] + cur[1]) - (prev[0] + prev[1])
        return round(100 * dbusy / dtotal) if dtotal > 0 else None

    def fast(self, d):
        out = {}
        uptime = num(d.get("uptime"))
        if uptime is not None:
            booted = datetime.now(timezone.utc) - timedelta(seconds=uptime)
            # Recomputed every poll it would drift by a second or two and write
            # a new state each time; only a real reboot moves it.
            if self.booted_at is None or abs((booted - self.booted_at).total_seconds()) > 120:
                self.booted_at = booted.replace(microsecond=0)
            out["booted_at"] = self.booted_at.isoformat()

        mem = dict(
            (k.strip(), num(v, int))
            for k, v in (p.split(":", 1) for p in str(d.get("meminfo", "")).split(";") if ":" in p)
        )
        if mem.get("MemTotal") and mem.get("MemAvailable") is not None:
            out["mem_used"] = round(100 * (1 - mem["MemAvailable"] / mem["MemTotal"]))

        # The thermal file reads a literal 0 for about 80 s after boot.
        temp = num(d.get("soc_temp"), int)
        if temp and not (uptime is not None and uptime < 90):
            out["soc_temp"] = temp
        out["cpu_load"] = self.cpu_utilisation(d.get("stat"))

        wash = d.get("pnwash_state")
        out["panel_wash_state"] = wash.strip() if isinstance(wash, str) else None

        out["power_state"] = luna(d, "power").get("state")
        out["foreground_app"] = luna(d, "app").get("appId") or None

        pic = luna(d, "picture")
        settings, dim = pic.get("settings") or {}, pic.get("dimension") or {}
        out["picture_mode"] = settings.get("pictureMode")
        out["oled_light"] = num(settings.get("backlight"), int)
        dr = dim.get("dynamicRange")
        out["dynamic_range"] = DYNAMIC_RANGE.get(dr, dr) if dr else None
        return out

    def full(self, d):
        out = {}
        usage = luna(d, "panel").get("panelUsageTime")
        panel_hours = round(usage / 6, 1) if isinstance(usage, (int, float)) else None
        out["panel_hours"] = panel_hours

        # Whole panel hours, unlike panelUsageTime's 10-minute units.
        r = luna(d, "refresher")
        # A short refresh runs at the next power-off once this reaches 0.
        if panel_hours is not None and isinstance(r.get("offrsLastTime"), int) and isinstance(r.get("offrsInterval"), int):
            left = r["offrsLastTime"] + r["offrsInterval"] - panel_hours
            out["hours_until_short_refresh"] = max(0.0, round(left, 1))
        if panel_hours is not None and isinstance(r.get("jbLastTime"), int) and isinstance(r.get("jbInterval"), int):
            out["hours_until_pixel_refresher"] = round(r["jbLastTime"] + r["jbInterval"] - panel_hours)
        out["short_refresh_count"] = r.get("offrsCount")
        out["pixel_refresher_count"] = r.get("jbCount")

        props = luna(d, "props")
        out["firmware"] = props.get("firmwareVersion")
        out["model"] = props.get("modelName")
        out["webos"] = props.get("sdkVersion")

        # "Battery = 52(M) 35(L)"; the first figure, as lg-webos-mqtt reads it.
        m = re.search(r"Battery\s*=\s*(\d+)", str(d.get("remote") or ""), re.I)
        out["remote_battery"] = int(m.group(1)) if m else None
        out["acr_running"] = "ON" if d.get("acr") else "OFF"
        self.slow = out
        return out


def sensor(key, name, unit=None, device_class=None, state_class=None, icon=None,
           category=None):
    cmp = {
        "p": "sensor",
        "unique_id": f"{NODE}_{key}",
        "name": name,
        "value_template": (
            "{%% if value_json.%s is defined and value_json.%s is not none %%}"
            "{{ value_json.%s }}{%% endif %%}" % (key, key, key)
        ),
    }
    for k, v in (("unit_of_measurement", unit), ("device_class", device_class),
                 ("state_class", state_class), ("icon", icon),
                 ("entity_category", category)):
        if v:
            cmp[k] = v
    return cmp


def binary(key, name, device_class, category=None):
    cmp = {
        "p": "binary_sensor",
        "unique_id": f"{NODE}_{key}",
        "name": name,
        "device_class": device_class,
        "payload_on": "ON",
        "payload_off": "OFF",
        "value_template": "{{ value_json.%s }}" % key,
    }
    if category:
        cmp["entity_category"] = category
    return cmp


def build_discovery(slow):
    cmps = {
        "power_state": sensor("power_state", "Power state", icon="mdi:power"),
        "foreground_app": sensor("foreground_app", "Foreground app", icon="mdi:application"),
        "picture_mode": sensor("picture_mode", "Picture mode", icon="mdi:palette"),
        "dynamic_range": sensor("dynamic_range", "Dynamic range", icon="mdi:hdr"),
        "oled_light": sensor("oled_light", "OLED light", "%", icon="mdi:brightness-6"),
        "soc_temp": sensor("soc_temp", "SoC temperature", "°C", "temperature", "measurement"),
        "cpu_load": sensor("cpu_load", "CPU utilisation", "%", icon="mdi:cpu-32-bit"),
        "mem_used": sensor("mem_used", "Memory used", "%", icon="mdi:memory"),
        "booted_at": sensor("booted_at", "Booted at", device_class="timestamp",
                            category="diagnostic"),
        "panel_hours": sensor("panel_hours", "Panel hours", "h", "duration",
                              "total_increasing", icon="mdi:television"),
        "hours_until_short_refresh": sensor("hours_until_short_refresh",
                                            "Hours until short refresh", "h",
                                            icon="mdi:timer-sand"),
        "hours_until_pixel_refresher": sensor("hours_until_pixel_refresher",
                                              "Hours until Pixel Refresher", "h",
                                              icon="mdi:timer-sand"),
        "short_refresh_count": sensor("short_refresh_count", "Short refreshes",
                                      icon="mdi:counter", category="diagnostic"),
        "pixel_refresher_count": sensor("pixel_refresher_count", "Pixel Refresher runs",
                                        icon="mdi:counter", category="diagnostic"),
        "panel_wash_state": sensor("panel_wash_state", "Panel wash state",
                                   icon="mdi:shimmer", category="diagnostic"),
        "firmware": sensor("firmware", "Firmware", icon="mdi:chip", category="diagnostic"),
        "remote_battery": sensor("remote_battery", "Magic Remote battery", "%", "battery",
                                 category="diagnostic"),
        "acr_running": binary("acr_running", "ACR running", "running", "diagnostic"),
        "root_problem": binary("root_problem", "Root access", "problem"),
    }
    dev = {"ids": [NODE], "name": "LG C1", "mf": "LG",
           "mdl": slow.get("model") or "OLED55C14LB"}
    # HA rejects the whole device payload if sw is null, which it is until the
    # first successful full poll.
    if slow.get("firmware"):
        dev["sw"] = slow["firmware"]
    return {
        "dev": dev,
        "o": {"name": "tv-metrics"},
        "state_topic": STATE_TOPIC,
        "availability_topic": AVAIL_TOPIC,
        "payload_available": "online",
        "payload_not_available": "offline",
        "qos": 0,
        "cmps": cmps,
    }


def main():
    if not MQTT_PASS:
        log("MQTT_PASS is empty — refusing to start")
        return 1

    reader = Reader()
    try:
        client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,
                             client_id=f"{NODE}-metrics")
    except AttributeError:
        client = mqtt.Client(client_id=f"{NODE}-metrics")
    client.username_pw_set(MQTT_USER, MQTT_PASS)
    client.will_set(AVAIL_TOPIC, "offline", retain=True)

    availability = {"value": "offline"}

    def publish_discovery(cl):
        payload = build_discovery(reader.slow)
        cl.publish(DISCOVERY_TOPIC, json.dumps(payload), retain=True)
        log(f"discovery published: {len(payload['cmps'])} entities")

    def on_connect(cl, _u, _f, rc, *_):
        failed = rc.is_failure if hasattr(rc, "is_failure") else rc != 0
        if failed:
            log(f"connect failed: {rc}")
            return
        log("connected")
        publish_discovery(cl)
        cl.publish(AVAIL_TOPIC, availability["value"], retain=True)

    client.on_connect = on_connect
    client.connect(MQTT_HOST, MQTT_PORT, keepalive=60)
    client.loop_start()

    running = {"go": True}

    def stop(*_):
        running["go"] = False

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    polls, last_ok, firmware = 0, False, None
    while running["go"]:
        mode = "full" if (not last_ok or polls % FULL_EVERY == 0) else "fast"
        status, data = ssh(mode)
        if status == "offline":
            if availability["value"] != "offline":
                log("tv unreachable")
            availability["value"] = "offline"
            client.publish(AVAIL_TOPIC, "offline", retain=True)
            reader.reset()
            last_ok = False
        else:
            payload = {"root_problem": "ON" if status == "problem" else "OFF"}
            if status == "ok":
                if mode == "full":
                    reader.full(data)
                payload.update(reader.slow)
                payload.update(reader.fast(data))
                if reader.slow.get("firmware") != firmware:
                    firmware = reader.slow.get("firmware")
                    publish_discovery(client)
            if availability["value"] != "online":
                log(f"tv reachable ({status})")
            availability["value"] = "online"
            client.publish(STATE_TOPIC, json.dumps(payload), retain=True)
            client.publish(AVAIL_TOPIC, "online", retain=True)
            last_ok = status == "ok"
        polls += 1
        for _ in range(INTERVAL):
            if not running["go"]:
                break
            time.sleep(1)

    log("shutting down")
    client.publish(AVAIL_TOPIC, "offline", retain=True)
    client.loop_stop()
    client.disconnect()
    return 0


if __name__ == "__main__":
    sys.exit(main())
