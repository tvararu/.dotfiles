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

## 2026-08-30: alignment pass

Audited against the Omarchy boxes and brought level. What changed and
why, newest state first.

### Update procedure

```bash
yay -Syu                 # zfs-dkms rebuilds against the new kernel: ~10 min
dkms status              # must show zfs/<ver>, <new kernel>: installed BEFORE rebooting
yay -Rns $(pacman -Qdtq) # orphans
sudo reboot              # only now; no zpool scrub / ufw reload between upgrade and reboot
```

A reboot with `dkms status` still on the old kernel comes up without
ZFS. `pacman-cleanup-hook` prunes the cache to the last two versions
automatically. `mkinitcpio.conf.pacnew` (stock `systemd`/`microcode`/
`kms` hooks) was reviewed and dropped — the `udev` hook set in place
works and `amd-ucode.img` is loaded as its own initrd.

### Network

NetworkManager only. `systemd-networkd` was also enabled (archinstall
templates), so both managed `enp4s0` and `wlp3s0` at once — two DHCP
clients per link and `systemd-resolved` tripping its start limit at
boot. networkd is disabled and `/etc/systemd/network` moved to
`network.archinstall-disabled`. Wifi stays on autoconnect as a second
path in. The router pins the wired MAC to a fixed address, so the LAN
address survives lease churn. `resolved` sits behind Tailscale's
`100.100.100.100`.

`/etc/resolv.conf` must stay a **symlink to
`../run/systemd/resolve/stub-resolv.conf`** (mode `stub`), as on the
Omarchy boxes. As a plain file it becomes a three-way fight —
NetworkManager rewrites it when a link activates, tailscaled detects
the "trample", rewrites it back and *restarts resolved* each time —
and five rounds of that at boot trip resolved's start limit
(`start-limit-hit`, tailscale.com/s/dns-fight). With the symlink,
NM and tailscaled both detect resolved and configure it over the bus;
nothing writes the file. Fixed 2026-08-30 after the first post-upgrade
reboot surfaced it.

### Boot

systemd-boot, single entry, `linux-lts` only. `/boot` is mounted
`fmask=0077,dmask=0077` — the previous `0022` made `bootctl` log
"security hole" twice per boot. vfat ignores `mount -o remount` for
masks; umount/mount to apply.

### Docker

`data-root` is `/home/deity/docker` (`/etc/docker/daemon.json`)
because `/` is 18 GB. It looks like cruft in `$HOME` and is not.
`sys/sol/docker-compose.yml` is the tracked base; anything not for the
public repo goes in an untracked `~/docker-compose.override.yml`, the
same arrangement as t1.

### Units

Hand-made units that survive: none in `/etc/systemd/system` beyond
what packages ship. Removed: `manele.service` (a yt-dlp collector that
had been failing on a missing binary since the docker wrapper replaced
the package), `backup.*` (target script's directory gone), and a spent
one-shot user timer. Six orphaned `/usr/lib/modules/<old-kernel>` dirs
from past dkms builds were deleted.

### Incus

Removed together with its only VM on 2026-08-30 (`incus lxcfs` plus
the qemu/edk2/dnsmasq tail, 242 packages). `incusbr0` and the `local`
storage pool were deleted first, and the eleven `incusbr0` ufw rules
afterwards — `ufw status numbered`, delete from the highest number down — `incus storage delete` refuses while
the default profile still references them: `incus profile device
remove default root` and `… eth0` first.

### Tooling

- `stow claude` links `~/.claude/CLAUDE.md` and `skills/`
- Claude Code, codex and gh come from mise (`mise/.config/mise/config.toml`),
  the native installer's `~/.local/bin/claude` and
  `~/.local/share/claude` are gone
- `sys/sol/sudo-passwordless` (installed to `~/.local/bin`) is a port
  of `omarchy-sudo-passwordless`: `sudo-passwordless 60` opens a
  60-minute NOPASSWD window via `/etc/sudoers.d/99-nopasswd-$USER` and
  a transient timer removes it. Run with no argument to close early.
  This is how remote agent sessions get root without a TTY
- No `hostname` binary here (no `inetutils`); fish config uses
  `$hostname`

## Metrics to Home Assistant

Since 2026-08-30 sol publishes host health to the mosquitto broker on
t1 (`tcp://100.73.138.96:1883`, tailnet-only via Serve) with MQTT
discovery, exactly like t1. Full plumbing notes: `sys/t1/maintenance.md`
under *Host metrics*.

- **Publisher**: `sys/host-metrics.py`, run by `sol-metrics.service`
  (copied into `/etc/systemd/system/`, never symlinked)
- **Credentials**: `/etc/sol-metrics.env`, mode 0600 — broker host,
  `sol` user, password
- **Packages**: `lm_sensors smartmontools python-paho-mqtt`; no
  `sensors-detect` needed, the chips are already in hwmon
- **Cadence**: sensors every 30 s; SMART and ZFS every 10 minutes.
  SATA SMART runs `smartctl -n standby` so it never wakes a sleeping
  drive
- **What sol adds over t1**: per-disk temperature and the four
  spinning-rust failure attributes for the three IronWolfs and the WD
  Red, plus `zfs_pool_health` / `capacity` / `scrub_age` /
  `scrub_errors`
- Three HA automations notify the phone: pool not ONLINE, scrub older
  than 40 days, any disk over 50 °C for 10 minutes
