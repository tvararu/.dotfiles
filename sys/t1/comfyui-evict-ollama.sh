#!/usr/bin/env bash
# Unload every resident ollama model so ComfyUI can have the card.
#
# ollama has no awareness of other GPU processes. It holds VRAM until
# OLLAMA_KEEP_ALIVE expires - 2h here, deliberately - or until something stops
# it. llama-server routinely holds 29 GB of the 5090's 32 GB, which leaves
# ComfyUI enough for its ~498 MiB CUDA context but nothing for a checkpoint:
# ltx-2-19b-distilled.safetensors alone is 41 GB on disk.
#
# This script never fails the unit, and comfyui.service calls it with a `-`
# prefix to make that explicit. A ComfyUI that starts on a contended card
# renders slowly; a ComfyUI that refuses to start is a page that never loads
# with no explanation anywhere the user will look.
set -uo pipefail

# The CLI defaults to 127.0.0.1:11434 but the daemon binds the tailnet address,
# so without this every call below says "could not connect to ollama server".
# Same value as fish/.config/fish/config.fish sets interactively.
export OLLAMA_HOST=${OLLAMA_HOST:-t1:11434}

TIMEOUT=${EVICT_TIMEOUT:-30}

# NR>1 skips the header. NF guards against the trailing blank line ollama emits
# when nothing is loaded, which would otherwise read as a model named "".
loaded() {
  ollama ps 2>/dev/null | awk 'NR>1 && NF {print $1}'
}

if ! models=$(loaded); then
  echo "Could not reach ollama at ${OLLAMA_HOST}; starting ComfyUI without evicting" >&2
  exit 0
fi

if [ -z "$models" ]; then
  echo "No ollama model resident, nothing to evict"
  exit 0
fi

# Stop by name rather than restarting the daemon. A restart would also drop the
# API listener, so anything mid-request would get a connection error instead of
# a slow answer.
while read -r model; do
  [ -z "$model" ] && continue
  echo "Evicting ollama model ${model} to free VRAM for ComfyUI"
  ollama stop "$model" || echo "Failed to stop ${model}, continuing anyway" >&2
done <<< "$models"

# `ollama stop` returns as soon as the daemon accepts it, but the runner process
# needs a moment to exit and release its CUDA context. ComfyUI does not allocate
# model VRAM until the first render, so this wait is belt and braces rather than
# load-bearing - hence a short timeout and no failure on expiry.
deadline=$(( $(date +%s) + TIMEOUT ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  [ -n "$(loaded)" ] || break
  sleep 0.5
done

if free=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null); then
  echo "ComfyUI starting with ${free} MiB free VRAM"
else
  echo "Evicted, but could not read free VRAM from nvidia-smi"
fi

exit 0
