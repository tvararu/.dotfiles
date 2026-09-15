#!/bin/sh
# smbd snapshots interface addresses at start. If enp7s0 or tailscale0 has
# no IPv4 yet, it binds loopback only and stays that way. Fail the start
# instead so Restart=on-failure retries until both addresses exist.
set -eu

i=0
while [ "$i" -lt 60 ]; do
	if ip -4 -o addr show dev enp7s0 2>/dev/null | grep -q ' inet ' \
		&& ip -4 -o addr show dev tailscale0 2>/dev/null | grep -q ' inet '; then
		exit 0
	fi
	i=$((i + 1))
	sleep 0.5
done

echo "smb-wait-ifaces: enp7s0 or tailscale0 has no IPv4 yet" >&2
exit 1
