#!/usr/bin/env bash
# Stop the ComfyUI container, but not while it is still rendering.
#
# The proxy's idle timer counts connections, not work. Queueing a long render and
# then closing the tab drops the connection count to zero, so without this guard
# the container would be killed mid-render at the timeout. A video job can run for
# many minutes, and the output would be lost with no error the user ever sees.
set -euo pipefail

CONTAINER=${CONTAINER:-comfyui}
PORT=${BACKEND_PORT:-8189}
DRAIN=${DRAIN_TIMEOUT:-1800}

# /prompt reports pending and running jobs together, which is exactly the
# question here. Anything unreachable or unparseable means the container is
# already gone or wedged, and waiting on it would just burn the stop timeout.
deadline=$(( $(date +%s) + DRAIN ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  remaining=$(curl -sf --max-time 2 "http://127.0.0.1:${PORT}/prompt" 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["exec_info"]["queue_remaining"])' 2>/dev/null) \
    || remaining=""

  [ -z "$remaining" ] && break
  [ "$remaining" -eq 0 ] && break

  echo "Waiting for ${remaining} queued job(s) before stopping ComfyUI"
  sleep 10
done

docker stop "$CONTAINER" >/dev/null
