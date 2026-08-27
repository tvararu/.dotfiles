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

Jellyfin runs as a Docker container (`network_mode: host`, `restart:
unless-stopped`). Docker starts on boot, so it self-restores — there is no
systemd unit. **`sys/sol/docker-compose.yml` is the source of truth** (it replaced
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

## HDR: do not enable Jellyfin's tone mapping

HDR10/HDR10+ sources **cannot be tone mapped in hardware on sol.** Every backend is dead on Vega 8 / RADV Raven / Mesa 24.0.9:

| Backend | Result |
| ------- | ------ |
| OpenCL | absent in container — `Failed to get number of OpenCL platforms: -1001` |
| Vulkan / libplacebo | `Failed mapping frame id 0` — dma-buf import broken |
| `tonemap_vaapi` (VPP) | Intel-only; radeonsi has no VPP tone mapping |
| software @ full 4K | **0.79× realtime** — unusable |

With `EnableTonemapping=false` (the current, correct setting) Jellyfin emits
`setparams=…bt709` before `scale_vaapi`, which only **relabels** BT.2020/PQ as
BT.709 without converting it — washed-out, grey colour. **Turning tone mapping on
makes it worse**, because the only remaining path is the 0.79× software one.

So: for HDR sources, **direct play and let the client tone map**. On a LAN that is
free and looks correct; macOS/Safari handle it natively. Only cap the bitrate when
genuinely bandwidth-limited, and accept wrong colour if you do.

A chain that does work at **~2.2× realtime**, if it is ever worth wiring up
manually, scales on the GPU *first* so the software tonemap runs on ~9× fewer
pixels:

```
scale_vaapi=w=1280:h=580:format=p010,hwdownload,format=p010le,\
tonemapx=tonemap=bt2390:format=nv12,hwupload=derive_device=vaapi
```

Jellyfin cannot generate this; it would need a working OpenCL ICD (Mesa rusticl) or
an ffmpeg wrapper.

## Exposing Jellyfin publicly (temporary)

Tailscale Funnel publishes Jellyfin at `https://sol.gentoo-bangus.ts.net/` with a
real cert. `tailscaled` terminates TLS and dials `127.0.0.1:8096`, so **no ufw rule
and no router change are needed** and the LAN stays closed.

`OperatorUser` is `deity`, so these need no `sudo`:

```bash
tailscale funnel --bg 8096        # on
tailscale funnel status
tailscale funnel --https=443 off  # off
```

- **WebSockets work**, but only over HTTP/1.1. The listener negotiates h2 by ALPN,
  and over h2 the `Upgrade` header is illegal and gets stripped — a WS handshake
  there returns 404. Browsers open a separate HTTP/1.1 connection for `wss://`, so
  this is invisible in practice. When testing by hand, `curl --http1.1` or the
  result is misleading.
- Funnel only accepts public ports **443, 8443, 10000**.
- The hostname lands in Certificate Transparency logs as soon as the cert issues —
  assume scanners find it within hours. Jellyfin has no real brute-force
  protection, so use a throwaway limited user, not the admin account, and turn the
  funnel off afterwards.
- Tailscale's AUP discourages bulk media distribution over Funnel; it is for
  lending someone an episode, not a permanent public server.
- **Cap the bitrate in the client before watching.** Left on Auto, a client that
  advertises HEVC/HDR support gets a *direct stream*: Jellyfin copies the video
  untouched (`-codec:v copy`) and only converts audio. The S02 4K HDR files are
  **~15 Mbps**, which neither Funnel's relay nor a home uplink will carry, so
  playback stalls repeatedly. sol is not the bottleneck — remuxing runs at ~62×
  realtime. Picking an explicit quality (e.g. 1080p / 4 Mbps) makes Jellyfin
  actually transcode down, and VAAPI does that at ~2.5–3.5× realtime: comfortable
  for *one* stream, not two.
