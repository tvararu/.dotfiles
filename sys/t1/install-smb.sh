#!/bin/sh
# Copy Samba config and the wait drop-in, then restart smbd.
# Run: sudo sh /home/deity/.dotfiles/sys/t1/install-smb.sh
set -eu

ROOT=/home/deity/.dotfiles/sys/t1

install -m 644 "$ROOT/smb.conf" /etc/samba/smb.conf
install -d -m 755 /etc/systemd/system/smb.service.d
install -m 644 "$ROOT/smb.service.d/wait-ifaces.conf" \
	/etc/systemd/system/smb.service.d/wait-ifaces.conf

testparm -s
systemctl daemon-reload
systemctl restart smb.service

# Binding is not instant; wait for the LAN and tailnet listeners.
i=0
while [ "$i" -lt 20 ]; do
	if ss -tln | grep -q '192.168.8.192:445' \
		&& ss -tln | grep -q '100.73.138.96:445'; then
		ss -tln | grep -E ':139|:445'
		exit 0
	fi
	i=$((i + 1))
	sleep 0.25
done

echo "smb did not bind 192.168.8.192:445 and 100.73.138.96:445" >&2
ss -tln | grep -E ':139|:445' || true
exit 1
