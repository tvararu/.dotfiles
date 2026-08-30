#!/usr/bin/env python3
"""Publish host health metrics to MQTT for Home Assistant (t1 and sol).

Runs on the host rather than in a container so that nvidia-smi and smartctl are
directly available: the NVIDIA GPU is not represented in hwmon at all, and SMART
needs the block devices. A long-running daemon (rather than a timer) holds one
connection and registers a Last Will, so Home Assistant marks the entities
unavailable if this process dies instead of showing stale readings forever.

Sensors are keyed off libsensors chip names, never hwmonN paths: hwmon numbering
is not stable across reboots and would silently swap sensor identities.
"""

import json
import os
import shutil
import re
import signal
import subprocess
import sys
import time

import paho.mqtt.client as mqtt

MQTT_HOST = os.environ.get("MQTT_HOST", "127.0.0.1")
MQTT_PORT = int(os.environ.get("MQTT_PORT", "1883"))
MQTT_USER = os.environ.get("MQTT_USER", "t1")
MQTT_PASS = os.environ.get("MQTT_PASS", "")
NODE = os.environ.get("NODE_NAME", "t1")

INTERVAL = int(os.environ.get("INTERVAL", "30"))
# SMART attributes move slowly and polling wakes the device, so it gets its own
# much slower cadence. Matters little on NVMe, but sol's spinning disks later.
SMART_INTERVAL = int(os.environ.get("SMART_INTERVAL", "600"))

STATE_TOPIC = f"{NODE}/metrics/state"
AVAIL_TOPIC = f"{NODE}/metrics/availability"
DISCOVERY_TOPIC = f"homeassistant/device/{NODE}/config"

# Readings outside this range are broken sensors, not cold rooms. The board's
# sixth temp header is unconnected and reports -55C.
TEMP_MIN, TEMP_MAX = -40.0, 200.0


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def run(cmd, timeout=15):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.stdout if p.returncode == 0 else None
    except (OSError, subprocess.SubprocessError):
        return None


def slug(text):
    return re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")


def pci_suffix(addr):
    """0000:0d:00.0 -> 0d00, matching how libsensors names PCI chips."""
    try:
        _, bus, devfn = addr.split(":")
        dev, fn = devfn.split(".")
        return "%04x" % ((int(bus, 16) << 8) | (int(dev, 16) << 3) | int(fn))
    except (ValueError, IndexError):
        return None


def nvme_drives():
    """Map libsensors chip name -> {slug, label, dev} for each NVMe drive.

    Keyed by model rather than kernel name: nvme0/nvme1 enumeration order is not
    guaranteed across reboots, which would swap the two drives' history.
    """
    out = {}
    base = "/sys/class/nvme"
    if not os.path.isdir(base):
        return out
    for name in sorted(os.listdir(base)):
        try:
            with open(f"{base}/{name}/model") as f:
                model = f.read().strip()
            addr = os.path.basename(os.path.realpath(f"{base}/{name}/device"))
        except OSError:
            continue
        suffix = pci_suffix(addr)
        if not suffix:
            continue
        label = re.sub(r"^Samsung\s+SSD\s+", "", model)
        out[f"nvme-pci-{suffix}"] = {
            "slug": slug(model),
            "label": label,
            "dev": f"/dev/{name}",
        }
    return out


def read_sensors():
    raw = run(["sensors", "-j"])
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        # Some libsensors versions emit bare `inf` for unpopulated limits.
        try:
            return json.loads(re.sub(r":\s*-?inf", ": null", raw))
        except json.JSONDecodeError:
            log("sensors -j returned unparseable JSON")
            return {}


def feature(chip, name, key):
    """Pull one reading out of the nested sensors -j structure."""
    try:
        val = chip[name][key]
    except (KeyError, TypeError):
        return None
    return None if val is None else round(float(val), 1)


def temp(chip, name, key):
    val = feature(chip, name, key)
    if val is None or not (TEMP_MIN < val < TEMP_MAX):
        return None
    return val


def find_chip(data, prefix):
    for key, val in data.items():
        if key.startswith(prefix):
            return val
    return None


NVIDIA_FIELDS = [
    "temperature.gpu",
    "fan.speed",
    "power.draw",
    "utilization.gpu",
    "clocks.sm",
    "clocks_event_reasons.hw_thermal_slowdown",
    "clocks_event_reasons.sw_thermal_slowdown",
    "clocks_event_reasons.hw_power_brake_slowdown",
]


def read_nvidia():
    raw = run(
        ["nvidia-smi", "--query-gpu=" + ",".join(NVIDIA_FIELDS),
         "--format=csv,noheader,nounits"]
    )
    if not raw or not raw.strip():
        return {}
    parts = [p.strip() for p in raw.strip().splitlines()[0].split(",")]
    if len(parts) != len(NVIDIA_FIELDS):
        return {}

    def num(v):
        try:
            return round(float(v), 1)
        except ValueError:
            return None

    def flag(v):
        return "ON" if v.lower() in ("active", "yes", "1", "true") else "OFF"

    return {
        "gpu_temp": num(parts[0]),
        "gpu_fan": num(parts[1]),
        "gpu_power": num(parts[2]),
        "gpu_util": num(parts[3]),
        "gpu_clock": num(parts[4]),
        "gpu_hw_thermal": flag(parts[5]),
        "gpu_sw_thermal": flag(parts[6]),
        "gpu_power_brake": flag(parts[7]),
    }


def read_smart(drives):
    out = {}
    for info in drives.values():
        raw = run(["smartctl", "-j", "-a", info["dev"]], timeout=30)
        if not raw:
            continue
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            continue
        health = data.get("nvme_smart_health_information_log", {})
        s = info["slug"]
        out[f"nvme_{s}_wear"] = health.get("percentage_used")
        out[f"nvme_{s}_power_on_hours"] = health.get("power_on_hours")
        out[f"nvme_{s}_media_errors"] = health.get("media_errors")
        out[f"nvme_{s}_spare"] = health.get("available_spare")
        warn = health.get("critical_warning")
        out[f"nvme_{s}_warning"] = "OFF" if warn in (0, None) else "ON"
    return out


def sata_drives():
    """Map /dev/disk/by-id ata-* disks (whole devices, not partitions)."""
    out = {}
    base = "/dev/disk/by-id"
    try:
        names = sorted(os.listdir(base))
    except OSError:
        return out
    for name in names:
        if not name.startswith("ata-") or "-part" in name:
            continue
        model = name[4:]
        out[name] = {
            "slug": slug(model),
            "label": model.replace("_", " "),
            "dev": f"{base}/{name}",
        }
    return out


def read_smart_sata(drives):
    """SMART for spinning disks. -n standby returns without waking a sleeping
    drive; its readings simply stay at their last published value."""
    out = {}
    for info in drives.values():
        raw = run(["smartctl", "-j", "-n", "standby", "-a", info["dev"]],
                  timeout=30)
        if not raw:
            continue
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            continue
        s = info["slug"]
        temp_c = data.get("temperature", {}).get("current")
        if temp_c is not None:
            out[f"sata_{s}_temp"] = temp_c
        poh = data.get("power_on_time", {}).get("hours")
        if poh is not None:
            out[f"sata_{s}_power_on_hours"] = poh
        attrs = {a.get("id"): a for a in
                 data.get("ata_smart_attributes", {}).get("table", [])}
        for attr_id, key in ((5, "reallocated"), (187, "uncorrectable"),
                             (197, "pending"), (198, "offline_uncorrectable")):
            a = attrs.get(attr_id)
            if a is not None:
                out[f"sata_{s}_{key}"] = a.get("raw", {}).get("value")
        passed = data.get("smart_status", {}).get("passed")
        if passed is not None:
            out[f"sata_{s}_failing"] = "OFF" if passed else "ON"
    return out


def zfs_pools():
    if not shutil.which("zpool"):
        return []
    raw = run(["zpool", "list", "-H", "-o", "name"])
    return raw.split() if raw else []


def read_zfs(pools):
    out = {}
    for pool in pools:
        raw = run(["zpool", "list", "-H", "-o", "capacity,health", pool])
        if raw:
            try:
                cap, health = raw.split()
                out[f"zfs_{pool}_capacity"] = int(cap.rstrip("%"))
                out[f"zfs_{pool}_health"] = "OFF" if health == "ONLINE" else "ON"
            except ValueError:
                pass
        raw = run(["zpool", "status", pool], timeout=30)
        if raw:
            m = re.search(r"scrub repaired .* with (\d+) errors on (.+)$",
                          raw, re.M)
            if m:
                out[f"zfs_{pool}_scrub_errors"] = int(m.group(1))
                try:
                    end = time.mktime(time.strptime(m.group(2).strip(),
                                                    "%a %b %d %H:%M:%S %Y"))
                    out[f"zfs_{pool}_scrub_age"] = round(
                        (time.time() - end) / 86400.0, 1)
                except ValueError:
                    pass
    return out


class CpuUtil:
    """Percentage busy since the previous sample, from /proc/stat."""

    def __init__(self):
        self.prev = None

    def read(self):
        try:
            with open("/proc/stat") as f:
                fields = [int(x) for x in f.readline().split()[1:]]
        except (OSError, ValueError):
            return None
        idle = fields[3] + (fields[4] if len(fields) > 4 else 0)
        total = sum(fields)
        prev, self.prev = self.prev, (idle, total)
        if prev is None:
            return None
        d_idle, d_total = idle - prev[0], total - prev[1]
        if d_total <= 0:
            return None
        return round(100.0 * (d_total - d_idle) / d_total, 1)


def read_cpu_freq():
    """Mean current frequency in MHz across cores.

    AMD exposes no throttle flag without an out-of-tree module, so frequency
    read alongside temperature is the throttling proxy.
    """
    vals = []
    base = "/sys/devices/system/cpu"
    try:
        cpus = [d for d in os.listdir(base) if re.fullmatch(r"cpu\d+", d)]
    except OSError:
        return None
    for cpu in cpus:
        try:
            with open(f"{base}/{cpu}/cpufreq/scaling_cur_freq") as f:
                vals.append(int(f.read().strip()))
        except (OSError, ValueError):
            continue
    return round(sum(vals) / len(vals) / 1000.0, 0) if vals else None


def read_proc():
    out = {}
    try:
        with open("/proc/loadavg") as f:
            out["load1"] = float(f.read().split()[0])
    except (OSError, ValueError, IndexError):
        pass
    try:
        mem = {}
        with open("/proc/meminfo") as f:
            for line in f:
                k, _, v = line.partition(":")
                mem[k] = int(v.split()[0])
        total, avail = mem.get("MemTotal"), mem.get("MemAvailable")
        if total and avail is not None:
            out["mem_used"] = round(100.0 * (total - avail) / total, 1)
    except (OSError, ValueError, IndexError):
        pass
    try:
        with open("/proc/uptime") as f:
            out["uptime"] = round(float(f.read().split()[0]) / 86400.0, 2)
    except (OSError, ValueError, IndexError):
        pass
    return out


def collect(drives, cpu_util):
    data = read_sensors()
    out = {}

    k10 = find_chip(data, "k10temp-")
    if k10:
        out["cpu_tctl"] = temp(k10, "Tctl", "temp1_input")
        out["cpu_tccd1"] = temp(k10, "Tccd1", "temp3_input")

    amd = find_chip(data, "amdgpu-")
    if amd:
        out["igpu_temp"] = temp(amd, "edge", "temp1_input")
        out["igpu_power"] = feature(amd, "PPT", "power1_input")

    board = find_chip(data, "gigabyte_wmi-")
    if board:
        for i in range(1, 7):
            val = temp(board, f"temp{i}", f"temp{i}_input")
            if val is not None:
                out[f"board_temp{i}"] = val

    nic = find_chip(data, "r8169")
    if nic:
        out["nic_temp"] = temp(nic, "temp1", "temp1_input")

    for chip_name, info in drives.items():
        chip = data.get(chip_name)
        if not chip:
            continue
        s = info["slug"]
        out[f"nvme_{s}_composite"] = temp(chip, "Composite", "temp1_input")
        out[f"nvme_{s}_hotspot"] = temp(chip, "Sensor 1", "temp2_input")
        out[f"nvme_{s}_nand"] = temp(chip, "Sensor 2", "temp3_input")

    out.update(read_nvidia())
    out.update(read_proc())
    out["cpu_freq"] = read_cpu_freq()
    out["cpu_util"] = cpu_util.read()
    return out


def sensor(key, name, unit=None, device_class=None, icon=None, category=None):
    cmp = {
        "p": "sensor",
        "unique_id": f"{NODE}_{key}",
        "name": name,
        "state_class": "measurement",
        # Render empty (-> unknown) rather than the string "None" when a reading
        # is missing, which would otherwise spam the HA log with parse warnings.
        "value_template": (
            "{%% if value_json.%s is defined and value_json.%s is not none %%}"
            "{{ value_json.%s }}{%% endif %%}" % (key, key, key)
        ),
    }
    if unit:
        cmp["unit_of_measurement"] = unit
    if device_class:
        cmp["device_class"] = device_class
    if icon:
        cmp["icon"] = icon
    if category:
        cmp["entity_category"] = category
    return cmp


def binary(key, name, device_class="problem"):
    return {
        "p": "binary_sensor",
        "unique_id": f"{NODE}_{key}",
        "name": name,
        "device_class": device_class,
        "payload_on": "ON",
        "payload_off": "OFF",
        "value_template": "{{ value_json.%s }}" % key,
    }


def dmi(field):
    try:
        with open(f"/sys/class/dmi/id/{field}") as f:
            return f.read().strip()
    except OSError:
        return "unknown"


def kernel_version():
    try:
        with open("/proc/sys/kernel/osrelease") as f:
            return f.read().strip()
    except OSError:
        return "unknown"


def build_discovery(drives, sata, pools, present):
    cmps = {}

    def add(key, cmp):
        if key in present:
            cmps[key] = cmp

    add("cpu_tctl", sensor("cpu_tctl", "CPU package", "°C", "temperature"))
    add("cpu_tccd1", sensor("cpu_tccd1", "CPU die", "°C", "temperature"))
    add("cpu_util", sensor("cpu_util", "CPU utilisation", "%", icon="mdi:cpu-64-bit"))
    add("cpu_freq", sensor("cpu_freq", "CPU frequency", "MHz", "frequency"))
    add("load1", sensor("load1", "Load average", icon="mdi:chart-line"))
    add("mem_used", sensor("mem_used", "Memory used", "%", icon="mdi:memory"))
    add("uptime", sensor("uptime", "Uptime", "d", icon="mdi:clock-outline",
                         category="diagnostic"))

    add("gpu_temp", sensor("gpu_temp", "GPU", "°C", "temperature"))
    add("gpu_fan", sensor("gpu_fan", "GPU fan", "%", icon="mdi:fan"))
    add("gpu_power", sensor("gpu_power", "GPU power", "W", "power"))
    add("gpu_util", sensor("gpu_util", "GPU utilisation", "%", icon="mdi:expansion-card"))
    add("gpu_clock", sensor("gpu_clock", "GPU clock", "MHz", "frequency"))
    add("gpu_hw_thermal", binary("gpu_hw_thermal", "GPU thermal slowdown (hardware)"))
    add("gpu_sw_thermal", binary("gpu_sw_thermal", "GPU thermal slowdown (software)"))
    add("gpu_power_brake", binary("gpu_power_brake", "GPU power brake"))

    add("igpu_temp", sensor("igpu_temp", "iGPU", "°C", "temperature"))
    add("igpu_power", sensor("igpu_power", "iGPU power", "W", "power"))

    add("nic_temp", sensor("nic_temp", "Network controller", "°C", "temperature"))

    # Unlabelled by the driver; identify which is which by watching load response.
    for i in range(1, 7):
        add(f"board_temp{i}", sensor(f"board_temp{i}", f"Board sensor {i}",
                                     "°C", "temperature"))

    for info in drives.values():
        s, label = info["slug"], info["label"]
        add(f"nvme_{s}_composite",
            sensor(f"nvme_{s}_composite", f"{label} composite", "°C", "temperature"))
        add(f"nvme_{s}_hotspot",
            sensor(f"nvme_{s}_hotspot", f"{label} controller", "°C", "temperature"))
        add(f"nvme_{s}_nand",
            sensor(f"nvme_{s}_nand", f"{label} NAND", "°C", "temperature"))
        add(f"nvme_{s}_wear",
            sensor(f"nvme_{s}_wear", f"{label} wear", "%",
                   icon="mdi:harddisk", category="diagnostic"))
        add(f"nvme_{s}_spare",
            sensor(f"nvme_{s}_spare", f"{label} spare", "%",
                   icon="mdi:harddisk", category="diagnostic"))
        add(f"nvme_{s}_power_on_hours",
            sensor(f"nvme_{s}_power_on_hours", f"{label} power-on hours", "h",
                   icon="mdi:clock-outline", category="diagnostic"))
        add(f"nvme_{s}_media_errors",
            sensor(f"nvme_{s}_media_errors", f"{label} media errors",
                   icon="mdi:alert-circle-outline", category="diagnostic"))
        add(f"nvme_{s}_warning",
            binary(f"nvme_{s}_warning", f"{label} SMART warning"))

    for info in sata.values():
        s, label = info["slug"], info["label"]
        add(f"sata_{s}_temp",
            sensor(f"sata_{s}_temp", f"{label} temperature", "°C",
                   "temperature"))
        add(f"sata_{s}_power_on_hours",
            sensor(f"sata_{s}_power_on_hours", f"{label} power-on hours", "h",
                   icon="mdi:clock-outline", category="diagnostic"))
        for key, word in (("reallocated", "reallocated"),
                          ("uncorrectable", "uncorrectable"),
                          ("pending", "pending"),
                          ("offline_uncorrectable", "offline uncorrectable")):
            add(f"sata_{s}_{key}",
                sensor(f"sata_{s}_{key}", f"{label} {word} sectors",
                       icon="mdi:harddisk-remove", category="diagnostic"))
        add(f"sata_{s}_failing", binary(f"sata_{s}_failing",
                                        f"{label} SMART failing"))

    for pool in pools:
        add(f"zfs_{pool}_health", binary(f"zfs_{pool}_health",
                                         f"ZFS {pool} degraded"))
        add(f"zfs_{pool}_capacity",
            sensor(f"zfs_{pool}_capacity", f"ZFS {pool} capacity", "%",
                   icon="mdi:database"))
        add(f"zfs_{pool}_scrub_age",
            sensor(f"zfs_{pool}_scrub_age", f"ZFS {pool} scrub age", "d",
                   icon="mdi:broom"))
        add(f"zfs_{pool}_scrub_errors",
            sensor(f"zfs_{pool}_scrub_errors", f"ZFS {pool} scrub errors",
                   icon="mdi:alert-circle-outline", category="diagnostic"))

    return {
        "dev": {
            "ids": [NODE],
            "name": NODE,
            "mf": dmi("board_vendor"),
            "mdl": dmi("board_name"),
            "sw": kernel_version(),
        },
        "o": {"name": "host-metrics"},
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

    drives = nvme_drives()
    sata = sata_drives()
    pools = zfs_pools()
    log(f"NVMe drives: {[d['label'] for d in drives.values()]}")
    log(f"SATA drives: {[d['label'] for d in sata.values()]}")
    log(f"ZFS pools: {pools}")

    def read_slow():
        out = read_smart(drives)
        out.update(read_smart_sata(sata))
        out.update(read_zfs(pools))
        return out

    cpu_util = CpuUtil()
    smart = read_slow()
    reading = collect(drives, cpu_util)
    reading.update(smart)

    # Arch ships paho-mqtt 1.6.1, which predates the CallbackAPIVersion
    # argument; accept either so a future package bump does not break this.
    try:
        client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,
                             client_id=f"{NODE}-metrics")
    except AttributeError:
        client = mqtt.Client(client_id=f"{NODE}-metrics")
    client.username_pw_set(MQTT_USER, MQTT_PASS)
    client.will_set(AVAIL_TOPIC, "offline", retain=True)

    published = {"discovery": False}

    # 1.x passes (client, userdata, flags, rc); 2.x appends properties, and rc
    # is a ReasonCode object rather than an int.
    def on_connect(cl, _u, _f, rc, *_):
        failed = rc.is_failure if hasattr(rc, "is_failure") else rc != 0
        if failed:
            log(f"connect failed: {rc}")
            return
        log("connected")
        cl.publish(AVAIL_TOPIC, "online", retain=True)
        # Republish discovery on every reconnect: a broker restart without
        # persistence would otherwise leave HA with no entities.
        payload = build_discovery(drives, sata, pools, set(reading))
        cl.publish(DISCOVERY_TOPIC, json.dumps(payload), retain=True)
        published["discovery"] = True
        log(f"discovery published: {len(payload['cmps'])} entities")

    client.on_connect = on_connect
    client.connect(MQTT_HOST, MQTT_PORT, keepalive=60)
    client.loop_start()

    running = {"go": True}

    def stop(*_):
        running["go"] = False

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    last_smart = 0.0
    while running["go"]:
        now = time.monotonic()
        if now - last_smart >= SMART_INTERVAL:
            smart = read_slow()
            last_smart = now
        payload = collect(drives, cpu_util)
        payload.update(smart)
        client.publish(STATE_TOPIC, json.dumps(payload), retain=True)
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
