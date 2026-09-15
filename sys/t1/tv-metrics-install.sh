#!/bin/sh
# One-shot root setup for tv-metrics on t1. Idempotent: an existing key,
# broker password or env file is kept. Prints only the public key.
#
#   sudo sh <repo>/sys/t1/tv-metrics-install.sh
set -eu

SYS=$(cd "$(dirname "$0")/.." && pwd)
TV=192.168.8.141

install -d -m 700 /etc/tv-metrics
[ -f /etc/tv-metrics/id_ed25519 ] ||
  ssh-keygen -q -t ed25519 -N '' -C tv-metrics@t1 -f /etc/tv-metrics/id_ed25519
# Pinned to the key the Mac has trusted since root was set up, so a rerun can
# never quietly accept a different TV.
HOSTKEY=SHA256:E++bHPBOklz6I82N/eT3jQdX29sYnS3a6m45I+KeT/s
if [ ! -f /etc/tv-metrics/known_hosts ]; then
  scan=$(ssh-keyscan -T 5 -t ed25519 "$TV" 2>/dev/null)
  got=$(printf '%s\n' "$scan" | ssh-keygen -lf - | awk '{print $2}')
  [ "$got" = "$HOSTKEY" ] || { echo "TV host key $got is not $HOSTKEY" >&2; exit 1; }
  printf '%s\n' "$scan" > /etc/tv-metrics/known_hosts
fi
chmod 600 /etc/tv-metrics/id_ed25519 /etc/tv-metrics/known_hosts

if [ ! -f /etc/tv-metrics.env ]; then
  pass=$(openssl rand -hex 24)
  # The directory, not the file: mosquitto_passwd rewrites via a temp file.
  docker run --rm -v /home/deity/srv/mosquitto:/m eclipse-mosquitto:2 \
    mosquitto_passwd -b /m/passwd tv "$pass"
  chown 1883:1883 /home/deity/srv/mosquitto/passwd
  chmod 600 /home/deity/srv/mosquitto/passwd
  # SIGHUP makes mosquitto reread its password file without a restart.
  docker kill -s HUP mosquitto >/dev/null
  umask 077
  printf 'MQTT_USER=tv\nMQTT_PASS=%s\n' "$pass" > /etc/tv-metrics.env
fi

install -D -m 644 "$SYS/tv-metrics.py" /usr/local/lib/tv-metrics/tv-metrics.py
install -m 644 "$SYS/t1/tv-metrics.service" /etc/systemd/system/tv-metrics.service
systemctl daemon-reload
# Until the public key is on the TV the service reports root_problem, which is
# harmless and turns off within a poll of the key landing.
systemctl enable --now tv-metrics
systemctl restart tv-metrics

# Public, and deity needs it to add the forced-command line on the TV.
install -m 644 /etc/tv-metrics/id_ed25519.pub /etc/tv-metrics.pub
echo "public key: $(cat /etc/tv-metrics.pub)"
