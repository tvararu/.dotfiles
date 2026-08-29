#!/usr/bin/env bash
# Free ComfyUI's resident checkpoints when ollama loads a model.
#
# The mirror of comfyui-evict-ollama.sh, for the other direction. systemd's
# Conflicts= cannot express this: ollama.service is always active, and what
# "spins up" is a llama-server runner inside the running daemon. The journal can
# see it. ollama logs "starting llama-server" about 2s before llama.cpp decides
# its layer split, and journalctl -f delivers a line through a pipe in ~450ms,
# which leaves enough margin for POST /free to land first.
#
# POST /free rather than `systemctl stop comfyui`, for three reasons:
#   - instant, where comfyui-stop.sh waits up to 30 min to drain the render queue
#   - it does not kill an in-flight render, which costs far more than a reload
#   - the container and any open tab stay alive
# It leaves ComfyUI's ~498 MiB CUDA context behind, which is noise against 32 GB.
set -uo pipefail

# The CONTAINER port, never 8188.
#
# 8188 is comfyui-proxy.socket. Connecting to it STARTS ComfyUI, which runs
# comfyui-evict-ollama.sh, which stops ollama - the exact event this script
# reacts to. Pointing this at 8188 would build an infinite loop between the two
# services. The systemctl guard below is the second line of defence.
PORT=${BACKEND_PORT:-8189}
MATCH=${MATCH:-starting llama-server}

echo "Watching ollama for model loads; will POST /free to 127.0.0.1:${PORT}"

# -n 0 starts at the tail: without it, every restart would replay the whole boot
# journal and fire once per historical model load.
journalctl -u ollama -f -n 0 --output=cat | while read -r line; do
  case "$line" in
    *"$MATCH"*) ;;
    *) continue ;;
  esac

  if ! systemctl is-active --quiet comfyui.service; then
    echo "ollama loaded a model; ComfyUI is not running, nothing to free"
    continue
  fi

  if curl -sf --max-time 5 -X POST "http://127.0.0.1:${PORT}/free" \
      -H 'Content-Type: application/json' \
      -d '{"unload_models": true, "free_memory": true}' >/dev/null; then
    echo "ollama loaded a model; freed ComfyUI's checkpoints"
  else
    echo "ollama loaded a model; POST /free to ComfyUI failed" >&2
  fi
done
