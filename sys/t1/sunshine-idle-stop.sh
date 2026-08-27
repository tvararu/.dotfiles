#!/usr/bin/env bash
# Stop Sunshine once no Moonlight session has run for IDLE_SECS.
#
# Sunshine creates a CUDA context during its startup encoder probe and holds it
# for the life of the process: 513 MiB of VRAM whether or not a client is
# connected. An active stream adds only ~79 MiB on top of that. On a box where
# llama-server routinely holds 29 GB of the 5090's 32 GB, the idle context is
# most of the cost and is worth reclaiming.
set -euo pipefail

UNIT=app-dev.lizardbyte.app.Sunshine.service
IDLE_SECS=${IDLE_SECS:-3600}
STAMP="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/sunshine-last-active"

# Nothing to stop. Drop the stamp so the next start begins on a clean clock.
if ! systemctl --user --quiet is-active "$UNIT"; then
  rm -f "$STAMP"
  exit 0
fi

# Sunshine binds UDP 47998-48000 (control, audio, video) when a session starts
# and closes them the moment the client disconnects; it holds no UDP socket while
# idle. That makes this a reliable probe in both directions. Match on the process
# name, not the port numbers, so a change to the `port` base does not silently
# break the check.
if ss -lnup | grep -q '"sunshine"'; then
  touch "$STAMP"
  exit 0
fi

# First idle observation. Start the clock rather than assume the worst.
if [ ! -e "$STAMP" ]; then
  touch "$STAMP"
  exit 0
fi

idle=$(( $(date +%s) - $(stat -c %Y "$STAMP") ))

# A stamp left behind by a previous Sunshine process would otherwise stop a
# freshly started one on the very next tick. Idle time cannot exceed how long
# this process has been up, so clamp it to the unit's own uptime. Both values are
# monotonic, so this is unaffected by clock steps.
started_us=$(systemctl --user show -p ActiveEnterTimestampMonotonic --value "$UNIT")
if [ -n "$started_us" ] && [ "$started_us" -gt 0 ]; then
  mono_now=$(cut -d' ' -f1 /proc/uptime)
  uptime_s=$(( ${mono_now%.*} - started_us / 1000000 ))
  [ "$idle" -gt "$uptime_s" ] && idle=$uptime_s
fi

if [ "$idle" -ge "$IDLE_SECS" ]; then
  echo "No session for ${idle}s (limit ${IDLE_SECS}s) - stopping Sunshine"
  systemctl --user stop "$UNIT"
  rm -f "$STAMP"
fi
