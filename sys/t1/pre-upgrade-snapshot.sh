#!/usr/bin/env bash
# Take a permanent, labelled snapshot before a risky system change.
#
# Not the same as `omarchy-snapshot create`, which passes `-c number` and so
# makes the snapshot eligible for auto-pruning. This one omits the cleanup
# algorithm entirely, the same shape snapper uses for its own "backup before
# restore" entries, so nothing deletes it later.
#
# Boot entries are a separate budget: limine-snapper-sync keeps only
# MAX_SNAPSHOT_ENTRIES (/etc/default/limine) of them. A snapshot that loses its
# boot entry still exists and is still restorable with `omarchy-snapshot
# restore` from a running system or a live USB.
#
# Usage: pre-upgrade-snapshot.sh [description]

set -euo pipefail

DESC="${1:-pre-quattro $(omarchy-version 2>/dev/null || echo unknown)}"

mapfile -t CONFIGS < <(sudo snapper --csvout list-configs | awk -F, 'NR>1 {print $1}')
[[ ${#CONFIGS[@]} -gt 0 ]] || { echo "no snapper configs found" >&2; exit 1; }

for config in "${CONFIGS[@]}"; do
  num=$(sudo snapper -c "$config" create --print-number \
          --description "$DESC" --userdata "important=yes")
  echo "created snapshot $num on config '$config': $DESC"
done

echo
sudo snapper -c root list | tail -5
echo
echo "restore with: omarchy-snapshot restore"
