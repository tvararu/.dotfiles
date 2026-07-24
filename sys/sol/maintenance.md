# sol

`sol` is my home NAS.

## Storage layout

NVMe `/dev/nvme0n1` (system):

| Part | FS         | Size   | Mount   |
| ---- | ---------- | ------ | ------- |
| p1   | vfat (ESP) | 484 MB | `/boot` |
| p2   | ext4       | 18 GB  | `/`     |
| p3   | ext4       | 201 GB | `/home` |

ZFS pool **`pool`** (data) — `/mnt/pool`:

- **raidz1**, 3× Seagate IronWolf **ST8000VN002 8 TB** (by-id `…ZPV00LSG`, `…ZPV00MX0`, `…ZPV00NRZ`)

## Services (Docker)

Jellyfin and Transmission run as Docker containers (`network_mode: host`,
`restart: unless-stopped`). Docker starts on boot, so they self-restore — there is
no systemd unit. **`sys/sol/docker-compose.yml` is the source of truth** (it replaced
ad-hoc `docker run` scripts). Images are pinned; bump them deliberately.

Deploy / recreate:

```bash
cd ~/.dotfiles/sys/sol
docker compose pull && docker compose up -d
```

- **Jellyfin** (`:8096`) — config `~/srv/jellyfin`, media from `/mnt/pool`.
  **HW transcode requires** the two `/dev/dri` devices **and** `group_add` GIDs
  **989 (render)** / **985 (video)**. These are host-specific Arch GIDs — if the host
  is ever rebuilt, re-check `getent group render video` and update the compose.
- **Transmission** (`:9091` web, `:51413` peer) — config `~/srv/transmission`,
  `PUID/PGID=1000`, data on `/mnt/pool`.
