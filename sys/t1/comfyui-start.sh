#!/usr/bin/env bash
# Start the ComfyUI container and block until it answers, for socket activation.
#
# ComfyUI holds ~498 MiB of VRAM for its CUDA context alone, with no model
# resident (`torch_vram_total` reads 0 in /system_stats). On a box where
# llama-server routinely takes 29 GB of the 5090's 32 GB, that idle context is
# worth reclaiming, and a container is cheap to bring back: ~14s to a served
# request.
set -euo pipefail

CONTAINER=${CONTAINER:-comfyui}
PORT=${BACKEND_PORT:-8189}
TIMEOUT=${START_TIMEOUT:-180}

docker start "$CONTAINER" >/dev/null

# systemd-socket-proxyd dials the backend as soon as this unit reports active and
# fails the connection if nothing answers, so returning early would turn every
# cold start into a failed first request. The client's TCP connection is already
# accepted by the socket unit and simply waits, which is why blocking here is
# correct rather than rude.
#
# Poll /system_stats rather than the port: the image's entrypoint publishes the
# port mapping immediately, so a port check would pass long before ComfyUI has
# imported its custom nodes and started serving.
deadline=$(( $(date +%s) + TIMEOUT ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  if curl -sf --max-time 2 "http://127.0.0.1:${PORT}/system_stats" >/dev/null 2>&1; then
    exit 0
  fi
  sleep 0.25
done

echo "ComfyUI did not answer on 127.0.0.1:${PORT} within ${TIMEOUT}s" >&2
exit 1
