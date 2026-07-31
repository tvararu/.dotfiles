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

## Media layout

The Jellyfin **Shows** library is scoped to `/media/Shows` only. Inside it,
`<Series> (<year>)/Season NN/Series SxxEyy Title.mkv` is the naming Jellyfin
indexes correctly; hardlinks are free within the single `pool` dataset, so a
clean tree can point at files stored elsewhere without copying.

Multiple qualities of one episode: identical base name plus ` - <label>`
(e.g. `… S02E02 - 2160p HDR.mkv` / `… S02E02 - 1080p SDR.mkv`).

**Naming alone is not enough for episodes.** Jellyfin auto-groups versions for
*movies* only; episodes just appear twice in the season list. The grouping does
exist, but must be triggered per episode — UI multi-select → *Merge items*, or
`POST /Videos/MergeVersions?Ids=a,b`. Re-run after any scan that adds versions.
Native support is proposed in jellyfin PR #16239, unmerged as of 2026-07.

Merging by `(series, season, episode)` alone is **destructive**: shows with a/b/c
segments per slot, and specials collected into S00E00, legitimately share one
episode number across genuinely different files. Match on identical base names
*and* equal runtimes before merging anything.
