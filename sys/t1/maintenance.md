# t1

This is a log of the various customisations I've done to my Omarchy setup.

## CLI Tools

```bash
yay -S fish git-delta lsd mosh tmux
```

## Remote administration

- `sudo` prompts for a password and cannot run unattended. For privileged work
  driven from a remote or automated session, write a script and run it as a
  single `sudo sh <path>` — one prompt, and the steps stay reviewable before
  they execute.
- Run docker compose from `$HOME`. `~/docker-compose.yml` symlinks to
  `.dotfiles/sys/t1/docker-compose.yml`, and it is that symlink which makes
  `$HOME` the project directory so `~/.env` resolves. Running from `sys/t1/`
  instead resolves the credentials in it to **empty strings** with no error —
  which silently breaks transmission's auth. `name: t1` in the file pins the
  project name regardless of where it is invoked.

## Keyboard: Apple GB ISO Layout

```
# ~/.config/hypt/input.conf
kb_layout = gb
kb_variant = mac
```

```bash
hyprctl reload
fcitx5 -r -d
```

## Keyboard: Fast Repeat Rate

```
# ~/.config/hypr/input.conf
repeat_rate = 100
repeat_delay = 150
```

## Keyboard: Fn Keys as Media Keys

fnmode=1 is media keys default, fnmode=2 is F-keys default.

```
# /etc/modprobe.d/hid_apple.conf
options hid_apple fnmode=1
```

```bash
sudo mkinitcpio -P  # regenerate initramfs
echo 1 | sudo tee /sys/module/hid_apple/parameters/fnmode  # apply now
```

## External Monitor Brightness (DDC/CI)

Exposes external monitors as backlight devices so SwayOSD/brightnessctl work with brightness keys.

```bash
sudo pacman -S ddcutil
yay -S ddcci-driver-linux-dkms-git
```

```bash
# find your i2c bus number
ddcutil detect

# load modules and register device (replace i2c-3 with your bus)
sudo modprobe i2c-dev ddcci ddcci-backlight
echo 'ddcci 0x37' | sudo tee /sys/bus/i2c/devices/i2c-3/new_device

# verify
brightnessctl -l | grep ddcci
```

Persistence:

```
# /etc/modules-load.d/ddcci.conf
i2c-dev
ddcci
ddcci-backlight
```

```
# /etc/udev/rules.d/99-ddcci.rules
# get ATTR{name} from: cat /sys/bus/i2c/devices/i2c-3/name
ACTION=="add", SUBSYSTEM=="i2c", ATTR{name}=="NVIDIA i2c adapter 3 at 1:00.0", RUN+="/bin/sh -c 'echo ddcci 0x37 > /sys/bus/i2c/devices/i2c-3/new_device'"
```

## Viture Luma Pro Mirror (1920x1200)

Set the UPERFECT to `1920x1200` first, then mirror the Viture output to it.

```bash
# source display (UPERFECT, on the NVIDIA HDMI)
hyprctl keyword monitor "HDMI-A-1,1920x1200@59.95,0x0,1"

# find first non-UPERFECT output (when Viture is connected)
GLASSES=$(hyprctl monitors all | awk '/^Monitor /{print $2}' | grep -v '^HDMI-A-1$' | head -n1)

# mirror Viture to UPERFECT at 1920x1200
hyprctl keyword monitor "$GLASSES,1920x1200@60,0x0,1,mirror,HDMI-A-1"
```

If no second monitor appears in `hyprctl monitors all`, the USB-C port/cable is not exposing DisplayPort Alt-Mode yet.

## LUKS: Clevis Initramfs Hook

Boot-time LUKS handling goes through `clevis`. The current binding state of this
machine is deliberately not recorded here — `clevis luks list -d <partition>`
reports it, and `lsblk -f` finds the partition. Bind and unbind per upstream
clevis docs; binding never removes the passphrase slot, so a passphrase always
stays a valid unlock path.

The hook wiring is the Omarchy-specific part, and the only bit worth writing down:

```bash
sudo pacman -S --needed clevis tpm2-tools tpm2-tss
yay -S mkinitcpio-clevis-hook
```

`clevis` must come before `encrypt`:

```
# /etc/mkinitcpio.conf.d/omarchy_hooks.conf
HOOKS=(base udev plymouth keyboard autodetect microcode modconf kms keymap consolefont block clevis encrypt filesystems fsck btrfs-overlayfs)
```

```bash
sudo limine-mkinitcpio
```

Rebuilding is only needed for hook changes. A bind or unbind does not need one —
the binding lives in a LUKS2 token in the partition header, not in the
initramfs. The `tpm_crb` driver behind `/dev/tpm0` on this board is built into
the kernel, so no TPM module has to be pulled into the image either.

After binding, prove the TPM actually releases the key before rebooting into a
prompt you cannot answer:

```bash
sudo clevis luks pass -d <partition> -s <slot> >/dev/null && echo TPM-UNSEAL-OK
```

That runs the same unseal the boot hook does; the redirect keeps the recovered
passphrase off the screen.

## Boot: Disable Limine Timeout

```
# /boot/limine.conf
timeout: 0
graphics: yes
```

## Network

Behind a GL.iNet GL-AXT1800 (Slate AX) as the main router, uplinked to the room's
wall ethernet. Wired primary, wireless fallback.

- **Router LAN**: `192.168.8.0/24`, gateway `192.168.8.1` — picked to avoid
  colliding with docker (`172.17`/`172.19`/`172.20.0.0/16`) and incus
  (`10.123.55.0/24`)
- **Wired**: `enp7s0` holds the default route.
  `/etc/systemd/network/20-ethernet.network` sets `DHCP=yes` and `RouteMetric=100`
  against wlan0's `600`, so plugging in takes over with no configuration
- **Wireless**: managed by iwd, not NetworkManager. wlan0 stays associated with
  `AutoConnect`, so it picks up the default route if the cable drops

### Router administration

GL.iNet firmware 4.x sits on OpenWrt 23.05, so `uci` and `fw4` work directly and
the stock web UI is not the only way in.

```bash
ssh root@192.168.8.1     # key auth; ssh-copy-id once from a new host
uci show firewall
fw4 reload               # after uci commit firewall
```

- `br-lan` bridges the ethernet ports and both radios, so wired and wireless
  clients share one L2 domain and mDNS crosses between them without a reflector
- The 2.4GHz AP is a separate `wifi-iface` from the 5GHz one and shipped both
  disabled and `hidden='1'`. 2.4GHz-only IoT gear needs it enabled and visible
- dnsmasq answers for `t1` with **both** interface addresses, so anything
  resolving it by name may get the Wi-Fi one. Use the wired address explicitly
  where it matters
- Per-client internet blocking is documented under Home Assistant below

## Tailscale

```bash
yay -S tailscale
sudo systemctl enable --now tailscaled
sudo tailscale set --operator=$USER
tailscale up
```

### Docker: start after Tailscale

Docker containers that bind to Tailscale IPs fail to map ports if Tailscale isn't up yet. Fix by ordering Docker after Tailscale:

```bash
sudo mkdir -p /etc/systemd/system/docker.service.d
echo -e '[Unit]\nAfter=tailscaled.service' | sudo tee /etc/systemd/system/docker.service.d/after-tailscale.conf
sudo systemctl daemon-reload
```

**This is not sufficient, and it bit us on 2026-08-26.** `tailscaled` is
`Type=notify`, but it signals readiness when the daemon and its local API are up
— *not* when `tailscale0` has been assigned its address. Docker starts into that
gap. On the 2026-08-26 boot:

```
08:50:27  tailscaled active (notify ready)
08:50:28  llama-qwen38 starts -> docker-proxy fails to bind 100.73.138.96:8001
08:50:30  docker active
```

The container came up **healthy with no published port at all** — the
healthcheck curls itself from inside the namespace, so nothing reported a
problem. `docker port llama-qwen38` printed nothing for a day. Symptoms to
recognise:

```bash
docker port <container>            # silent = nothing published
ss -ltn | grep <port>              # no listener
docker inspect <c> -f '{{json .NetworkSettings.Ports}}'   # {}
```

**Do not bind published ports to a Tailscale IP.** Publish to `127.0.0.1` and
put `tailscale serve` in front (see *Tailscale Serve* below) — loopback always
exists at container start, so the race cannot happen. `llama-server` was
converted on 2026-08-27. Anything still binding `100.73.138.96` has this bug
latent.

### Tailscale accepts inbound before ufw sees it

`tailscaled` installs its own `ts-input` chain that ACCEPTs traffic arriving on
`tailscale0` for this node, and it runs ahead of ufw's default-deny. So **every
host-bound service is reachable from the tailnet with no ufw rule at all** —
`8123` (Home Assistant) and `9091` (Transmission) have no `allow` rule of any
kind and both answer over the tailnet.

The consequence worth keeping in mind: **ufw here governs LAN and WAN exposure
only.** Tightening a ufw rule does not reduce what the tailnet can reach — that
is gated by device membership, not by the firewall.

### Docker published ports over Tailscale (ufw-docker)

The ufw-docker ruleset (in `/etc/ufw/after.rules`) only allows RFC1918 LAN
sources through to Docker-published ports; Tailscale sources are CGNAT
(`100.64.0.0/10`), so their SYNs are silently dropped in `DOCKER-USER`
(`[UFW DOCKER BLOCK]` in kernel log). Host-bound services (INPUT path, e.g.
llama-server on the tailscale IP) are unaffected — only the FORWARD/DNAT path
to containers is filtered. Symptom: connection *timeout* from tailnet peers
while closed ports get *refused*.

Allow per-port with `ufw route allow` (checked before the drop rules):

```bash
sudo ufw route allow proto tcp from 100.64.0.0/10 to any port 3724 comment 'wow auth from tailnet'
sudo ufw route allow proto tcp from 100.64.0.0/10 to any port 8085 comment 'wow world from tailnet'
sudo ufw route allow proto tcp from 100.64.0.0/10 to any port 8888 comment 'playerbots tcp from tailnet'
```

Affected here, verified 2026-08-27 from a second tailnet node — these three are
the only Docker-published ports on the box, so they are the only ones blocked:

| Port | Service   |
| ---- | --------- |
| 8096 | jellyfin  |
| 8188 | comfyui   |
| 8675 | aitoolkit |

Everything else is `network_mode: host`. All three still work over the LAN,
which is what the RFC1918 allowance covers. The three `ufw route allow` rules
above are currently inert — no AzerothCore containers are running — as is the
`27036` Steam rule.

#### Tailscale Serve: the alternative that needs no firewall rule

For an **HTTP** service, `tailscale serve` sidesteps the problem entirely.
`tailscaled` dials `127.0.0.1:<port>` from the host, so the connection is
locally generated and never enters `FORWARD`/`DOCKER-USER`:

```bash
tailscale serve --bg 8096            # https://t1.gentoo-bangus.ts.net/      -> 127.0.0.1:8096
tailscale serve --bg --https=8443 8001  # https://t1.gentoo-bangus.ts.net:8443/ -> 127.0.0.1:8001
tailscale serve status
tailscale serve --https=443 off      # disable
```

Two services use it, both set up 2026-08-27:

| URL | Backend | Why |
|---|---|---|
| `https://t1.gentoo-bangus.ts.net/` | Jellyfin `127.0.0.1:8096` | tailnet peers were dropped in `DOCKER-USER` |
| `https://t1.gentoo-bangus.ts.net:8443/` | llama-server `127.0.0.1:8001` | published port raced tailscale0 at boot |

`/` on `:443` is taken by Jellyfin, so a second service needs either its own
HTTPS port (`--https=8443`, used here — no path rewriting, which matters for an
OpenAI-compatible API) or a subpath via `--set-path`. One cert covers every port.

No sudo, no ufw change, real Let's Encrypt cert, and it persists across reboots
— the config lives in `/var/lib/tailscale/tailscaled.state` and `tailscaled`
restores it on start. It does **not** survive `tailscale logout` or a state wipe.

Trade-offs: the stream is proxied through tailscaled rather than going direct,
the client URL becomes the MagicDNS name, and it only covers HTTP — raw TCP
needs `--tcp` or a `ufw route allow`. Whether the plain `http://t1:<port>` URL
still works on the LAN depends on the container's own bind, not on Serve:
Jellyfin still publishes `0.0.0.0:8096`, so `http://t1:8096` is unchanged;
llama-server publishes loopback only, so `http://t1:8001` is gone and Serve is
the only way in.

The HTTPS is incidental, not the point. Tailscale is already WireGuard, so the
transport is encrypted and the peer authenticated by public key; TLS on top adds
nothing on security grounds, including on hostile café Wi-Fi. It matters only for
browser secure-context features (PWA install, service workers), which the native
iOS app — the client that surfaced this — does not use.

## TPM-Backed SSH Keys

SSH keys stored in TPM hardware - private key never leaves the chip.

### Setup

```bash
yay -S ssh-tpm-agent
ssh-tpm-keygen -C "theo@vararu.org"  # empty PIN is fine with FDE
systemctl --user enable --now ssh-tpm-agent.socket
ssh-tpm-add ~/.ssh/id_ecdsa.tpm
```

### Git commit signing

```
# ~/.gitconfig.local
[user]
  signingkey = ~/.ssh/id_ecdsa.pub
[commit]
  gpgsign = true
[gpg]
  format = ssh
```

Add the SSH key to GitHub as both **SSH key** and **signing key**:

```bash
cat ~/.ssh/id_ecdsa.pub | wl-copy
```

## Neovim: Disable Markdown Rendering

```lua
-- ~/.config/nvim/lua/config/options.lua
vim.opt.conceallevel = 0
```

## XDG Directories Cleanup

Remove default XDG folders (Desktop, Documents, etc.) and prevent recreation:

```
# ~/.config/user-dirs.dirs
XDG_DESKTOP_DIR="$HOME"
XDG_DOCUMENTS_DIR="$HOME"
XDG_DOWNLOAD_DIR="$HOME/downloads"
XDG_MUSIC_DIR="$HOME"
XDG_PICTURES_DIR="$HOME"
XDG_PUBLICSHARE_DIR="$HOME"
XDG_TEMPLATES_DIR="$HOME"
XDG_VIDEOS_DIR="$HOME"
```

```
# ~/.config/user-dirs.conf
enabled=False
```

## Ghostty: Line-by-Line Scrolling

```
# ~/.config/ghostty/config
keybind = ctrl+shift+up=scroll_page_lines:-1
keybind = ctrl+shift+down=scroll_page_lines:1
```

## Idle/Lock Timings

```
# ~/.config/hypr/hypridle.conf
timeout = 3600  # 60min - screensaver
timeout = 3600  # 60min - lock screen
timeout = 3600  # 60min - screen off
```

## Removed Packages

```bash
# Office/Productivity
yay -Rns libreoffice-fresh xournalpp typora obsidian

# Printing (no printer)
yay -Rns cups cups-browsed cups-filters cups-pdf system-config-printer

# Media apps (overkill)
yay -Rns kdenlive obs-studio gpu-screen-recorder

# Messaging/Music (use web versions)
yay -Rns signal-desktop spotify localsend

# File system mounts (not using)
yay -Rns gvfs-mtp gvfs-nfs gvfs-smb

# Development (not needed)
yay -Rns ruby luarocks mariadb-libs postgresql-libs
yay -Rns python-gobject python-poetry-core python-terminaltexteffects

# Misc
yay -Rns asdcontrol tobi-try evince sushi ffmpegthumbnailer
```

Clean orphans after:

```bash
yay -Rns $(yay -Qdtq)
```

**These removals have consequences that were never followed up.** Five keybindings,
both screen-recording entry points and three Share menu entries still call binaries
removed here, and fail silently. See [omarchy-divergence.md](omarchy-divergence.md)
for the full audit against a vanilla Omarchy 3.8.5 VM, with an action checklist.

Note that Omarchy has since added `omarchy-remove-preinstalls`, which does most of
this list *and* swaps `bindings.conf` for `plain-bindings.conf` so the keybindings
go with the apps. Don't run it on this box — it would also strip the web apps and
TUI wrappers that are wanted here.

## QEMU VM (OpenClaw)

Ubuntu 24.04 VM for running OpenClaw agent.

### Setup

```bash
yay -S qemu-base cloud-image-utils

mkdir -p ~/vms
cd ~/vms

# Download Ubuntu cloud image
curl -L -O https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

# Create VM disk (40GB thin-provisioned)
cp noble-server-cloudimg-amd64.img openclaw.qcow2
qemu-img resize openclaw.qcow2 40G

# Create cloud-init config (direct root access)
cat > user-data << EOF
#cloud-config
hostname: openclaw
disable_root: false
ssh_authorized_keys:
  - $(cat ~/.ssh/id_ecdsa.pub)
package_update: true
packages:
  - curl
  - git
  - build-essential
EOF

echo "instance-id: openclaw" > meta-data
cloud-localds seed.img user-data meta-data

# First boot (applies cloud-init, runs in background)
qemu-system-x86_64 \
  -enable-kvm \
  -m 8G \
  -smp 4 \
  -cpu host \
  -drive file=openclaw.qcow2,if=virtio \
  -drive file=seed.img,if=virtio,format=raw \
  -nic user,hostfwd=tcp::2222-:22 \
  -display none \
  -serial none \
  -daemonize

# Wait for boot, then clean up
sleep 45
rm seed.img user-data meta-data
```

### Startup script

```bash
# ~/vms/openclaw.sh
#!/bin/bash
qemu-system-x86_64 \
  -enable-kvm \
  -m 8G \
  -smp 4 \
  -cpu host \
  -drive file=$HOME/vms/openclaw.qcow2,if=virtio \
  -nic user,hostfwd=tcp::2222-:22 \
  -device virtio-balloon-pci \
  -object rng-random,id=rng0,filename=/dev/urandom \
  -device virtio-rng-pci,rng=rng0 \
  -pidfile $HOME/vms/openclaw.pid \
  -display none \
  -serial none \
  -daemonize
```

```bash
chmod +x ~/vms/openclaw.sh
```

### Systemd service (auto-start on boot)

```bash
# ~/.config/systemd/user/openclaw.service
[Unit]
Description=OpenClaw VM
After=network.target

[Service]
Type=forking
PIDFile=/home/deity/vms/openclaw.pid
ExecStart=/home/deity/vms/openclaw.sh
Restart=on-failure

[Install]
WantedBy=default.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable openclaw
loginctl enable-linger $USER
```

### Manage VM

```bash
systemctl --user start openclaw
systemctl --user stop openclaw
systemctl --user restart openclaw
systemctl --user status openclaw
```

### Connect

```bash
# ~/.ssh/config.local
Host openclaw
    HostName localhost
    Port 2222
    User root
```

```bash
ssh openclaw
```

## Sunshine (Game Streaming via Moonlight)

Streams the desktop to a Mac (or anything else running Moonlight). The machine is
headless for this purpose: an HDMI dummy plug holds an output alive, Hyprland
renders to it, and Sunshine captures and encodes that output.

**The display lives on the RTX 5090's `HDMI-A-1`.** The AMD iGPU's `HDMI-A-2` is
unused. This reverses an earlier layout and the reversal matters, because of one
rule:

> Capture and encode must happen on the **same GPU**. Frames arrive as DMA-BUFs
> belonging to whichever card owns the scanout; the other card cannot import them.

With the plug on the 5090 that means `encoder = nvenc`, and **no `adapter_name`**
(it selects a VAAPI device and only makes sense when encoding on the iGPU).
Pointing the encoder at the wrong card does not fail cleanly — it produces
`Frame capture failed` in a loop and then segfaults Sunshine mid-handshake, which
Moonlight reports only as `Error code: -1`.

Do not trust `cardN` numbering; it is not stable across boots. Check the live
mapping instead:

```bash
for c in /sys/class/drm/card*-*; do [ -e "$c/status" ] && echo "$(basename $c) $(cat $c/status)"; done
```

### Capture method

On Hyprland + NVIDIA there is effectively **one** working option:

| Method | Verdict here |
|---|---|
| `wlr` | **In use.** wlroots screencopy (`wlgrab` in the logs). |
| `kms` | Enumerates an *empty* monitor list — nvidia-drm does not expose scanout framebuffers for kmsgrab-style capture. Works fine on the AMD iGPU. |
| `nvfbc` | No Wayland support. |
| `kwin` | Wrong compositor. |
| `x11` | Not applicable under Wayland. |

Newer builds also offer XDG portal / PipeWire capture, which is worth trying if
`wlr` ever regresses again.

### Install

```bash
yay -S sunshine-bin
```

Keep it current. `wlr` capture on a fractionally-scaled output was broken for
most of 2025 and fixed in the 2026.5 release; an 8-month-stale package presented
as a black screen with no obvious cause.

### Setup

```bash
# Only needed for kms capture, which is unused here — harmless to set.
# NOTE: a package upgrade wipes file capabilities, so re-apply after upgrading.
sudo setcap cap_sys_admin+p $(readlink -f $(which sunshine))

systemctl --user enable --now app-dev.lizardbyte.app.Sunshine.service
```

**The unit was renamed upstream** from `sunshine.service` to
`app-dev.lizardbyte.app.Sunshine.service`. The new unit declares
`Alias=sunshine.service`, so the short name works again — but only once the unit
is enabled, since the alias symlink is created by `enable`. After an upgrade that
crosses the rename, expect `Unit sunshine.service not found` until you enable the
new name.

Drop-ins are keyed to the real unit name, so they must live in
`~/.config/systemd/user/app-dev.lizardbyte.app.Sunshine.service.d/`. One is in
use, working around pipewire-pulse leaving the default source as a literal
`@DEFAULT_SOURCE@` token:

```
# .../app-dev.lizardbyte.app.Sunshine.service.d/pipewire-audio.conf
[Service]
Environment="XDG_RUNTIME_DIR=/run/user/1000"
Environment="PULSE_SERVER=unix:/run/user/1000/pulse/native"
```

Open `https://localhost:47990` to set credentials, then pair from Moonlight.

### Config

```
# ~/.config/sunshine/sunshine.conf
system_tray = disabled
capture = wlr
encoder = nvenc
audio_sink = sink-sunshine-stereo
```

`audio_sink` is pinned for the same pipewire-pulse reason as the drop-in.

### App config

No `prep-cmd` resolution switching. It existed to flip between 1080p for a TV and
1920x1200 for remote desktop; the TV is gone, the output is a dummy plug, and
`monitors.conf` now fixes a single mode. The old `sunshine-res` helper hardcoded
`HDMI-A-2` and had been silently doing nothing since the cable moved.

```json
// ~/.config/sunshine/apps.json
{
  "env": { "PATH": "$(PATH):$(HOME)/.local/bin" },
  "apps": [
    { "name": "Desktop", "image-path": "desktop.png" },
    {
      "name": "Steam Big Picture",
      "detached": ["setsid steam steam://open/bigpicture"],
      "prep-cmd": [{ "do": "", "undo": "setsid steam steam://close/bigpicture" }],
      "image-path": "steam.png"
    }
  ]
}
```

To stream at a different resolution than the host renders, prefer Moonlight's own
scaling over a `prep-cmd`; recent Sunshine handles scaled outputs natively.

### Monitor config

A catch-all rule, so the mode survives the plug moving ports:

```
# ~/.config/hypr/monitors.conf
env = GDK_SCALE,1.5
monitor = ,1920x1200@60,auto,1.5
```

Scale 1.5 means 1920x1200 physical but only **1280x800 logical** — a small
desktop. Fine for glasses or a portable panel, cramped for remote work. Drop to
`,1920x1200@60,auto,1` for more usable space.

### Firewall

```bash
sudo ufw allow 47984:48010/tcp
sudo ufw allow 47984:48010/udp
```

### Moonlight client settings

- Resolution: 1920x1200 (or "Native excluding notch" on Mac)
- Connect via the Tailscale IP — auto-uses LAN when on the same network
- **AV1 is available** on this setup (`av1_nvenc`). The AMD iGPU had no AV1
  encoder at all, so this is new since the move to the 5090.

### DPMS

`hypridle.conf` currently has no `dpms off` listener, so nothing here bites. If
one is ever added, exclude the streaming output: if DPMS blanks it Sunshine sees a
0x0 resolution and fails.

### Troubleshooting

Sunshine logs to the journal under the *real* unit name:

```bash
journalctl --user -u app-dev.lizardbyte.app.Sunshine.service -f
```

Add `min_log_level = 0` to `sunshine.conf` for verbose output — remember to remove
it, it produced a 17MB `~/.config/sunshine/sunshine.log` in minutes.

| Symptom | Cause |
|---|---|
| Moonlight `Error code: -1` | Sunshine crashed mid-handshake. Check for `core-dump` in the journal. |
| Black screen, session connects | Capture failing. Look for `Frame capture failed`. |
| `Frame capture failed` | Encoder on a different GPU than the display, or a stale build on a scaled output. |
| `Unit sunshine.service not found` | Upgrade crossed the unit rename; enable the new name. |

To confirm the compositor itself is rendering (rules out Sunshine entirely):

```bash
grim /tmp/test.png && ffmpeg -v quiet -i /tmp/test.png -vf scale=1:1 -f rawvideo -pix_fmt rgb24 - | od -An -tu1
```

Non-zero RGB means the desktop is live and the fault is in Sunshine's capture
path. `grim` uses shm buffers where Sunshine uses dmabuf, so `grim` succeeding
while Sunshine fails points at the dmabuf path specifically.

## HDMI Dummy Plug (Headless/Remote Access)

A 4K HDMI dummy plug keeps an output alive so Hyprland has something to render to
while the machine runs headless.

It sits on the **RTX 5090's `HDMI-A-1`**. An earlier note in this file claimed the
plug could not work there because the NVIDIA port ignores its HPD signal — that
limitation is real, but it is defeated by forcing an EDID at boot, which is
already wired up (see *UPERFECT EDID HDR Strip*):

```
drm.edid_firmware=HDMI-A-1:edid/uperfect-sdr.bin
```

The connector therefore comes up regardless of HPD, and reports the UPERFECT EDID
rather than the plug's own — so `hyprctl monitors` shows UPERFECT modes no matter
which of the two is physically attached. Mode selection comes from the
`monitors.conf` catch-all above.

## Ollama (native)

Runs natively as a systemd service rather than in docker — direct CUDA access on the RTX 5090, simpler ops, journald logs.

```bash
yay -S --needed ollama-cuda
sudo systemctl enable --now ollama.service
```

The package creates the `ollama` system user and `/var/lib/ollama` (700 perms, owned by `ollama:ollama`). The service unit sets `OLLAMA_MODELS=/var/lib/ollama` and binds `127.0.0.1:11434`.

Models live at `/var/lib/ollama/{blobs,manifests}`. To migrate from a previous docker setup that used `~/srv/ollama`:

```bash
sudo cp -a ~/srv/ollama/models/blobs     /var/lib/ollama/blobs
sudo cp -a ~/srv/ollama/models/manifests /var/lib/ollama/manifests
sudo chown -R ollama:ollama /var/lib/ollama
```

Exposed to the Tailscale tailnet only (not the LAN). A systemd drop-in binds directly to the tailscale IP, so the port never listens on `enp7s0` and no firewall rule is needed:

```bash
sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null <<'EOF'
[Unit]
After=tailscaled.service
Wants=tailscaled.service

[Service]
Environment="OLLAMA_HOST=100.73.138.96:11434"
EOF
sudo systemctl daemon-reload
sudo systemctl restart ollama
```

Reachable from other tailnet devices at `http://t1:11434` (MagicDNS) or `http://100.73.138.96:11434`. LAN clients get connection refused — the kernel rejects at bind level. `After=tailscaled.service` orders ollama after tailscale so `100.73.138.96` exists at bind time; the base unit's `Restart=on-failure` provides retry safety.

## llama-server (Qwen MTP)

Runs `ghcr.io/ggml-org/llama.cpp:server-cuda` via docker compose alongside ollama. Used instead of ollama because ollama doesn't support the MTP draft head yet and can't load these GGUFs cleanly (separate `mmproj` files). MTP speculative decoding gets ~300 tok/s on structured output vs ~100 tok/s without — 65 % draft acceptance on HTML generation in testing.

Three compose profiles, one model at a time — all three bind port 8001 and none of them fit in VRAM together:

| Profile  | Service            | Model                                    | Weights |
|----------|--------------------|------------------------------------------|---------|
| `a3b`    | `llama-qwen36-a3b` | `unsloth/Qwen3.6-35B-A3B-MTP-GGUF`       | 23 GB   |
| `qwopus` | `llama-qwopus`     | `Jackrong/Qwopus3.6-27B-v2-MTP-GGUF`     | 17 GB   |
| `qwen38` | `llama-qwen38`     | `unsloth/Qwen3.8-27B-GGUF`               | 18 GB   |

Start one with `docker compose up -d <service>` (profiles keep them out of a bare `compose up`). Stop whichever is running first.

- **Image**: `ghcr.io/ggml-org/llama.cpp:server-cuda` (tracks llama.cpp main; MTP merged upstream)
- **Model**: `unsloth/Qwen3.6-35B-A3B-MTP-GGUF:UD-Q4_K_XL`, auto-downloaded via `-hf` flag on first run (~23 GB)
- **Cache**: `~/srv/llama-server/cache` bind-mounted to `/root/.cache/huggingface` so the GGUF survives container recreates
- **Bind**: `127.0.0.1:8001:8001` — loopback only; the tailnet reaches it through
  Tailscale Serve on `:8443` (see below). Was `100.73.138.96:8001:8001` until
  2026-08-27, which raced tailscale0 at boot — see *Docker: start after Tailscale*
- **Endpoint**: OpenAI-compatible at `https://t1.gentoo-bangus.ts.net:8443/v1`
  (chat completions, models, embeddings). `http://t1:8001/v1` no longer resolves
  to anything — the port is not published off-host

Key flags in `command:`:

- `-ngl 99 -fa on --parallel 1` — all layers on GPU, flash attention on, single request slot (keeps KV cache small enough to fit the model + draft state in 32 GB VRAM next to ComfyUI)
- `--spec-type draft-mtp --spec-draft-n-max 6` — enables MTP, max 6 speculative tokens per step
- Sampling: `--temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.00 --presence-penalty 1.5` (Unsloth's recommended values for Qwen3.6)

VRAM coexistence: at full context the model uses ~31.5 GB / 32 GB. Won't fit alongside another GPU model loaded simultaneously. If ComfyUI is holding VRAM and llama-server fails to load, free ComfyUI's models with `curl -X POST http://localhost:8188/free -H 'Content-Type: application/json' -d '{"unload_models": true, "free_memory": true}'`.

### Qwen3.8 27B (profile `qwen38`)

Qwen3.8 shipped Aug 2026 with only two open sizes — a 27B dense and a 2.4T-A95B. There is **no A3B-class MoE in 3.8**, so this is not a like-for-like replacement for the 35B-A3B: it activates all 27B params per token instead of 3B, which costs roughly 3x decode speed for a better model. Both are kept; pick per task.

- **Model**: `unsloth/Qwen3.8-27B-GGUF:UD-Q4_K_XL` (~18 GB). The MTP head ships **inside the main repo** — there is no separate `-MTP-GGUF` repo for 3.8, unlike 3.6
- **Speed**: 97 tok/s measured on t1 (800-token generation, 0.56 draft acceptance, mean draft len 2.69). Compare ~300 tok/s for the A3B — the cost of a dense model
- **VRAM**: 25.7 GB / 32 GB loaded at the full 262 K context, so ComfyUI can still stay resident alongside it. The A3B cannot do this
- **`--spec-draft-n-max 3`**, not 6 — the 5090 sweet spot for this model. Worth re-sweeping 2–4 if it feels slow
- **`--presence-penalty 0.0`** — Qwen's thinking-mode recommendation. The `1.5` used for the A3B is the *non-thinking* value and hurts here
- **`-c 262144 --cache-type-k q4_0 --cache-type-v q4_0`** — the model's full native context. f16 KV would need ~17 GB and not fit; quantized KV costs ~28 KiB/token, so 262 K lands at 25.7 GB

#### Why 262144 and not higher

This is a **hybrid attention/SSM model**, not a pure transformer — the GGUF declares `full_attention_interval = 4` plus `ssm.*` keys, so only ~16 of its 65 layers keep a growing KV cache and the rest hold fixed-size SSM state. That is why context is far cheaper here than layer count suggests.

Measured ceiling on the 5090 (32 GB), q4_0 KV, probing until load failure:

| `-c`   | VRAM      | Notes                        |
|--------|-----------|------------------------------|
| 131072 | 22149 MiB |                              |
| 262144 | 25733 MiB | native max, no rope scaling  |
| 393216 | 29319 MiB | needs YaRN 1.5x              |
| 458752 | 31111 MiB | needs YaRN 1.75x             |
| 491520 | 32007 MiB | highest that loads — 98 % of the card |
| 524288 | —         | fails to load                |

Anything past 262 K needs `--rope-scaling yarn`, and llama.cpp's YaRN is **static** — the scale applies to every request regardless of actual length, so short prompts degrade too. Qwen advise against enabling it unless long contexts are genuinely the workload. Confirmed locally: at `--temp 0`, the 131072 and 262144 configs return byte-identical output while the YaRN config returns a consistently different one.

Decode speed is flat across all of these — 94.0 / 92.4 / 94.1 tok/s at 131072 / 262144 / 458752 (three deterministic runs each, ~1 tok/s spread). Attention cost tracks tokens *in* the cache, not the allocation, so raising `-c` is free until you actually fill it. Benchmark at `--temp 0`: at temp 1.0 the draft acceptance rate swings per generation and swamps the signal.
- Vision is compiled out via `--no-mmproj` (the model is natively multimodal). MTP does not support `-np > 1`, hence `--parallel 1`
- The image's baked-in healthcheck curls `:8080`, but all three services serve on `:8001`, so `docker ps` reports **unhealthy** forever. `llama-qwen38` overrides it; `a3b` and `qwopus` still show the false red. Nothing restarts on it — `unless-stopped` only acts on exit

Verify MTP is actually engaging after any flag change — the acceptance line only appears when the draft model loaded:

```bash
docker logs llama-qwen38 2>&1 | grep -E "draft acceptance|tokens per second"
```

## ComfyUI

ComfyUI via [mmartial/comfyui-nvidia-docker](https://github.com/mmartial/ComfyUI-Nvidia-Docker) on `ubuntu24_cuda13.1-latest`. The image clones upstream ComfyUI HEAD on first boot into a persistent venv at `~/srv/comfyui/`, so subsequent restarts skip the install step.

- **Port**: 8188
- **Run dir**: `~/srv/comfyui/` (venv, ComfyUI source, custom_nodes, uv cache — all persistent)
- **Models**: `~/models` bind-mounted to `/host_models`, symlinked into `/comfy/mnt/ComfyUI/models` by `user_script.bash`
- **Plugin bootstrap**: `~/srv/comfyui/user_script.bash` (mmartial auto-runs any file of that name)

### Custom nodes

Declared inline in `user_script.bash` — idempotent git-clone + `pip install -r requirements.txt` per repo:

| Node pack                       | Repo                                   |
| ------------------------------- | -------------------------------------- |
| VideoHelperSuite                | Kosinkadink/ComfyUI-VideoHelperSuite   |
| VFI (video frame interpolation) | GACLove/ComfyUI-VFI                    |
| comfy_mtb                       | melMass/comfy_mtb                      |
| Easy-Use                        | yolain/ComfyUI-Easy-Use                |
| MMAudio                         | kijai/ComfyUI-MMAudio                  |
| VAE-Utils                       | spacepxl/ComfyUI-VAE-Utils             |
| RES4LYF                         | ClownsharkBatwing/RES4LYF              |
| rgthree-comfy                   | rgthree/rgthree-comfy                  |
| sdxl_prompt_styler              | twri/sdxl_prompt_styler                |
| ComfyUI-LTXVideo                | Lightricks/ComfyUI-LTXVideo            |
| KJNodes                         | kijai/ComfyUI-KJNodes                  |
| Inpaint-CropAndStitch           | lquesada/ComfyUI-Inpaint-CropAndStitch |
| RMBG                            | 1038lab/ComfyUI-RMBG                   |

### Notes

- Bind-mounting models _inside_ the ComfyUI tree (e.g. `~/models:/comfy/mnt/ComfyUI/models`) breaks mmartial's init — Docker pre-creates the parent dir, mmartial then tries `git remote set-url` on a non-repo and loops on "subscript failed". Mount outside the tree and symlink in.
- `FORCE_CHOWN=true` is required — mmartial creates `/comfy/mnt/ComfyUI/` as root before chowning to `WANTED_UID`, and refuses to start if the perms don't match.
- The persistent venv means a `docker compose up -d --force-recreate comfyui` is fast (~30s); only image upgrades trigger a fresh torch+deps install.
- To upgrade ComfyUI itself: `git -C ~/srv/comfyui/ComfyUI pull && docker restart comfyui`.
- `user_script.bash` patches ComfyUI-VAE-Utils to PR #22 ([spacepxl/ComfyUI-VAE-Utils#22](https://github.com/spacepxl/ComfyUI-VAE-Utils/pull/22)) — restores `CustomVAE.decode()` after ComfyUI #11405/#11406 bypassed `decode_tiled_3d` and broke Qwen 2x decode (dark/burned output). Drop the patch block once upstream merges.

## Home Assistant (Qingping air monitor)

Home Assistant via the official `ghcr.io/home-assistant/home-assistant:stable` image, reading a Qingping Air Monitor Lite (CGDN1 — CO2, PM2.5, PM10, temperature, humidity) over HomeKit on the LAN. The point is local history and alerting without the vendor cloud: the sensor is firewalled off the internet at the router and still reports fine, because HomeKit Accessory Protocol is plain local IP once paired.

- **Port**: 8123, plus 21063 for the HomeKit bridge
- **Config**: `~/srv/homeassistant/` (root-owned — the official image ignores `PUID`/`PGID` and runs as root)
- **Networking**: `network_mode: host`, mandatory — HomeKit pairing and the bridge both need mDNS, which a published port cannot carry
- **Exposure**: ufw allows 21063/tcp and 5353/udp from the LAN only; 8123 stays LAN-blocked and is reached over tailscale
- **History**: no extra database. The recorder defaults to SQLite and its long-term statistics table is never purged — hourly min/max/mean kept forever for `state_class: measurement` sensors. `purge_keep_days` governs only full-resolution state

### Mode selection is a setup-time decision

The CGDN1 speaks HomeKit, Mi Home or Qingping+, and only one at a time. There is no on-device selector — the mode is decided by whichever app first adds it, and changing it means holding the top bar for 8 seconds to reset the network config and starting over.

HomeKit is the right choice here, but the obvious route is a trap: scanning the setup code in Apple Home pairs it *to Apple Home*, and HomeKit accessories pair to exactly one controller, so Home Assistant would get nothing. The working sequence is:

1. Add it in Apple Home by scanning the code. This joins it to Wi-Fi and fixes it in HomeKit mode.
2. Remove the accessory from Apple Home. This un-pairs it but leaves the Wi-Fi credentials intact.
3. Pair it in HA via `homekit_controller` using the same setup code.
4. Enable HA's HomeKit Bridge to publish it back to Apple Home.

The device is 2.4GHz only (802.11 b/g/n), so the router needs a 2.4GHz AP — the Slate's was present but its interface was both disabled and `hidden='1'`.

### Blocking it from the internet

A static DHCP lease pins its address, and a firewall rule in the `lan` zone matching its MAC rejects forward to `wan`. Set `option proto 'all'`, or fw4 emits TCP and UDP rules only and everything else still escapes. DNS and NTP need no exception: traffic to the router's own dnsmasq hits the `input` chain, not `forward`. The rule's counter climbing while HA keeps receiving readings is the proof it works.

### What the bridge round-trip costs

Everything arrives in HA intact — CO2 in ppm, PM2.5/PM10 densities, temperature, humidity, a 1–5 air-quality rating, and battery. Going back out through the bridge is lossier, so the bridge is filtered to only the entities that survive:

| Entity                | Survives  | Notes                                                                    |
| --------------------- | --------- | ------------------------------------------------------------------------ |
| CO2                   | Improved  | Becomes a `CarbonDioxideSensor`; HA adds peak-level and a `CarbonDioxideDetected` flag at 1000 ppm |
| Temperature, humidity | Yes       | Direct mapping                                                            |
| PM2.5, PM10           | Reshaped  | Two separate `AirQualitySensor` accessories, each with its own recomputed rating |
| Air quality rating    | **No**    | `SensorDeviceClass.AQI` has no branch in `get_accessory`                   |
| Battery               | **No**    | No battery branch, and `EntityCategory.DIAGNOSTIC` is excluded by default  |

No alerting is configured, deliberately — this is a history-first setup, reviewed in the morning rather than pushed. Worth knowing the options if that changes: Apple Home can notify on the `CarbonDioxideDetected` flag, but only with a home hub (HomePod or Apple TV) on the network, and Macs and iPhones stopped qualifying years ago. Failing that, the HA companion app works at the cost of relaying iOS push through Nabu Casa, or a self-hosted `ntfy` keeps the chain local.

### Notes

- `advertise_ip` must be set explicitly. Inside the container the hostname resolves to the tailscale address, so the bridge would otherwise advertise an IP no iOS device on the LAN can reach.
- t1 has ethernet and Wi-Fi on the same subnet, which makes mDNS ambiguous. `/etc/sysctl.d/30-arp-multihome.conf` sets `arp_ignore=1`/`arp_announce=2` and avahi is restricted to the wired interface. On Wi-Fi failover the advertised IP goes stale and HomeKit breaks until the cable is back — the fallback exists for SSH, not for HomeKit.
- Bluetooth gets `/run/dbus` and `NET_ADMIN`/`NET_RAW` despite this being a Wi-Fi setup. HA discovers `hci0` regardless and recreates the config entry on every start; without them it retries a failing scanner indefinitely. Deleting the entry does not stick.
- Keep the sensor on USB-C. On battery it powers itself off after 30 minutes (`power_off_time`), which looks exactly like the device going `Unavailable` for no reason.
- Do not enable the Qingping app's **Bluetooth Gateway** function — it is mutually exclusive with HomeKit.
- `attempted pair verify without being paired first` right after pairing is your other Apple devices racing the iCloud propagation of the pairing. It settles on its own.
- Keep the printed setup code. HA needs the same code and it is unrecoverable if lost.

## Host metrics (MQTT → Home Assistant)

t1 lives in a cupboard, so its own temperatures are recorded into Home Assistant alongside everything else. A Python daemon on the host publishes to a local Mosquitto broker using MQTT discovery; HA picks the sensors up as a single `t1` device. Recording only — no alerts and no automated mitigation.

The publisher runs on the **host, not in a container**, because the two most important sources are unreachable from inside one: the NVIDIA GPU is absent from hwmon entirely and only `nvidia-smi` can see it, and SMART needs the raw block devices.

- **Broker**: `eclipse-mosquitto:2`, bound to `127.0.0.1:1883`. The publisher is on the host and HA is host-networked, so nothing crosses the LAN and **no ufw rule is needed**
- **Broker config**: `sys/t1/mosquitto.conf`; credentials in `~/srv/mosquitto/passwd` (generated on the box with `mosquitto_passwd`, never committed), users `ha` and `t1`
- **Publisher**: `sys/t1/t1-metrics.py`, run by `t1-metrics.service` — **copied** into `/etc/systemd/system/`, deliberately not symlinked (see *The unit must not be symlinked from this repo* below). Edits to the `.py` apply after `systemctl restart t1-metrics`; edits to the unit need re-copying first
- **Credentials**: `/etc/t1-metrics.env`, mode 0600, read by the unit via `EnvironmentFile`
- **Intervals**: sensors and GPU every 30s; SMART every 10 minutes, since attributes move slowly and polling wakes the device
- **Retention**: every sensor is published with `state_class: measurement`, which is what puts it in HA's long-term statistics — hourly min/max/mean kept forever. Without it the data would silently vanish at `purge_keep_days`

### The unit must not be symlinked from this repo

`t1-metrics.service` was originally symlinked out of `sys/t1/` into `/etc/systemd/system/`, so that repo edits went live after a `daemon-reload`. On this machine that is a trap, and it stayed hidden until the first reboot after the service was set up:

```
t1-metrics.service: Failed to open /etc/systemd/system/t1-metrics.service: No such file or directory
```

This repo is checked out under `/home`, which lives on the encrypted root volume and is **not mounted at the point systemd loads units**. So the unit was simply unreadable at boot: `systemctl is-enabled` answered `enabled`, nothing started, `NRestarts=0`, and the boot journal held that one line and nothing further. Every reboot silently lost host telemetry, and since this setup runs recording-only with no alerting, nothing would have said so.

**There are two symlinks, and fixing one is not enough.** Replacing the unit with a real file still leaves `multi-user.target.wants/t1-metrics.service` pointing back into the repo — and *that* is the one systemd reads at boot to decide what to pull into the target. `systemctl is-enabled` reports `enabled` either way, because systemd does not validate a symlink's target, which is exactly what makes the half-fix look finished.

```bash
sudo install -m644 sys/t1/t1-metrics.service /etc/systemd/system/t1-metrics.service
sudo systemctl daemon-reload
sudo systemctl reenable --now t1-metrics
```

`reenable` is the step that rewrites the `*.wants/` symlink to the real path. Verify both, not just the unit:

```bash
systemctl show t1-metrics -p FragmentPath -p LoadState -p ActiveState
ls -l /etc/systemd/system/multi-user.target.wants/t1-metrics.service
```

Both paths should be under `/etc/systemd/system/`, with none pointing into `/home`.

**Only the unit file has to move.** `t1-metrics.py` stays in the repo: it is read at service *start*, long after `/home` is mounted — which is also why the unit sets `ProtectHome=read-only` rather than `yes`. The cost is that the unit no longer auto-syncs, so re-copy it whenever it changes here.

Generalises past this service: **a systemd unit cannot live behind a late mount**, and `is-enabled` is not evidence that one will start.

### What the hardware exposes

| Source | Provides |
| --- | --- |
| `k10temp` | CPU `Tctl`, `Tccd1` |
| `nvidia-smi` | 5090 temp, fan %, power, utilisation, clock, thermal-slowdown flags |
| `amdgpu` | iGPU edge temp and package power |
| `nvme` ×2 | composite / controller / NAND temps |
| `smartctl` | wear, spare, power-on hours, media errors, critical warning |
| `gigabyte_wmi` | six board temps, **unlabelled** |
| `r8169` | onboard NIC temp |

Fan RPM is **not available**. No driver on this board exposes `fan*_input`; the only fan reading of any kind is the GPU's, via `nvidia-smi`. See *Fan speeds* below.

### Idle baseline

Recorded 2026-08-24 at genuine idle (load 0.01, GPU 13W/180MHz), for comparison against later readings:

| Sensor | Idle | Throttles at |
| --- | --- | --- |
| NVMe 990 EVO Plus composite | 71.8°C | 80.8°C |
| NVMe 9100 PRO composite | 72.8°C | 83.8°C |
| CPU `Tctl` | 61.9°C | ~95°C |
| Board sensor 2 | 76°C | — |
| Onboard NIC | 70°C | 120°C |
| RTX 5090 | 56°C | ~88°C |

An NVMe with airflow idles at 35–50°C, so these are roughly 20°C high and about 9°C from throttling before any work starts. The machine is thermally constrained at rest, not merely at risk of it.

### Notes

- **Chip names, not `hwmonN` paths.** hwmon numbering is not stable across reboots, so the script keys off libsensors chip names. NVMe drives are identified by model for the same reason — `nvme0`/`nvme1` enumeration order is not guaranteed and would swap the two drives' history.
- **`acpitz` reads ~17°C and is fiction** — a fixed ACPI zone, excluded. `gigabyte_wmi` `temp6` reads −55°C (unconnected header) and is filtered by a sanity range.
- **Board sensors are unlabelled.** `temp1`–`temp5` are published as "Board sensor N"; identify which is which by watching load response before renaming.
- **AMD exposes no throttle flag** without an out-of-tree module, so CPU frequency is published alongside temperature as the proxy. The GPU has real flags (`clocks_event_reasons.*_thermal_slowdown`), which are the most direct evidence of heat constraint on the machine.
- **Arch ships paho-mqtt 1.6.1**, which predates the `CallbackAPIVersion` argument; the client construction accepts either API so a package bump does not break it.
- **`python-paho-mqtt` from the repos, not pip** — PEP 668 blocks `pip install` on Arch.
- **The service runs as root** because smartctl needs the block devices, so `PrivateDevices` is deliberately absent from the unit. `ProtectHome` is `read-only` rather than `yes` because the script itself lives in the repo under `/home`.
- **Last Will is the point of using a daemon** rather than a timer: if the publisher dies, HA marks the entities unavailable instead of showing stale readings indefinitely.

### Fan speeds

Deliberately not implemented. The board is a B850I AORUS PRO with an ITE Super I/O chip that has no in-kernel driver; RPM would need the out-of-tree [it87](https://github.com/frankcrawford/it87) DKMS module plus `acpi_enforce_resources=lax` on the kernel command line. That means editing `/etc/default/limine` and regenerating the UKI on a Clevis-unlocked machine, and the kernel's own it87 documentation warns of races and unexpected reboots when ACPI and the driver share the chip. Not worth it unless the recorded data raises a question only fan speed can answer.

### Adding sol later

The broker is the reusable part. Point a copy of the publisher at t1 over the tailnet — bind mosquitto to the tailnet address as the `llama-*` services already do, rather than exposing it to the LAN — and give sol its own broker user. Worth adding ZFS pool health, scrub status and per-drive temps there, and keeping the slow SMART interval since sol's disks actually spin.

## Eight Sleep (Pod 5)

Sleep and bed data from an Eight Sleep Pod 5, recorded alongside the bedroom air monitor. The point is the pairing: overnight CO2 and sleep quality land in the same recorder with long-term statistics, which makes "does ventilation actually improve sleep" a measurable question rather than a preference. Recording only — nothing writes back to the bed.

- **Integration**: [lukas-clarke/eight_sleep](https://github.com/lukas-clarke/eight_sleep), a custom component in `~/srv/homeassistant/custom_components/eight_sleep`
- **Version**: source tag `1.0.24.beta.5`. **The manifest inside it still reads `1.0.23`** — the author does not bump it for betas, so HA reports the older number. Check the directory contents, not the version HA displays
- **Config**: UI config flow, email and password only; `client_id`/`client_secret` are optional and left blank
- **Entities**: 52 — one set per bed side (bed/target temperature, heart rate, HRV, breath rate, sleep stage, fitness/quality/routine scores, time slept, presence start/end, alarms) plus hub-level water, priming and room temperature
- **Cloud polling**, 5-minute interval. There is no local path; the pod talks to Eight Sleep's servers and the integration polls their API

### Why the core integration is not used

Home Assistant still ships an `eight_sleep` integration, but it is a **removal stub**: its `async_setup_entry` does nothing except raise a permanent repair issue, and its config flow has no steps. HA removed it because the Eight Sleep API "now requires a unique secret which is inaccessible outside of their apps". A custom component of the same domain shadows the built-in one, which is how this works at all.

### The beta is required, not merely preferred

Latest stable is `1.0.23` (2026-02). The fix stopping the config flow from offering the Pod 5 *pillow* instead of the hub landed only in `1.0.24.beta.5`, along with a `KeyError: 'sku'` fix for incomplete hardware info. On stable, Pod 5 setup can select the wrong device entirely.

### Installed without HACS

HACS is installed at `custom_components/hacs` (release zip 2.0.5, extracted rather than `wget | bash`), but **its config flow is not completed** — that needs an interactive GitHub device-code login. It is not required for this integration: HACS only downloads a directory from a GitHub tag, which the release archive does directly. Complete the HACS setup if you want update notifications; until then, updating means re-extracting a newer tag.

### Notes

- **Credentials are stored in plaintext.** HA writes every integration's config entry to `/config/.storage/core.config_entries` unencrypted, mode 0644. This applies to the MQTT password too. The disk is LUKS-encrypted, but Clevis auto-unlocks at boot, so it protects a pulled drive and not a stolen running machine.
- **Presence and sleep stage are unreliable** by the author's own admission — Eight Sleep computes presence retroactively, so leaving the bed for an hour does not end it. The integration infers presence from heart-rate gaps instead. Do not build anything on either.
- **Bed temperature is only meaningful while the pod is active.**
- **Neither side may be in away mode during setup**, or session data is missing and setup can fail.
- **Nothing reaches Apple Home.** The HomeKit bridge filter is `include_entities`, an allowlist naming only the air monitor's sensors, so the bed's climate and alarm entities stay inside HA even though they are enabled.
- **The realistic failure mode is Eight Sleep rotating the client secret**, which breaks the integration until the maintainer extracts a new one. Account action over API use has not been reported.
- **Custom integrations break on HA updates** on the author's schedule, not Home Assistant's. Worth skimming release notes before updating HA.

## YouTube queue → Jellyfin

Saving a video to an unlisted playlist on a burner account gets it downloaded and into the Jellyfin YouTube library within the hour, with no further action. An hourly systemd timer runs the yt-dlp already installed on the host; there is no extra service, container, or database.

- **Queue playlist**: unlisted, on the burner account. The URL lives in `/etc/default/yt-queue` as `YT_QUEUE_URL`, mode 0600 — an unlisted playlist URL is a capability, and this repo is public and name-attributed
- **Downloader**: `~/.local/bin/yt-dlp`, the self-updating zipapp — **not** pacman's `/usr/bin/yt-dlp`
- **Units**: `sys/t1/yt-queue.{service,timer}` and `sys/t1/yt-dlp-update.{service,timer}`, **copied** into `/etc/systemd/system/`, deliberately not symlinked (see *The unit must not be symlinked from this repo* under the metrics section). Re-copy and `daemon-reload` after editing them here
- **Cadence**: hourly, `RandomizedDelaySec=5m`, `Persistent=true` so a missed run catches up after downtime
- **Dedup**: `--download-archive /mnt/aux/yt-queue/archive.txt`. This is the entire state machine — re-running is idempotent and costs one playlist fetch
- **Library**: files land in `/mnt/aux/media/youtube/<Uploader>/`, which Jellyfin watches with `EnableRealtimeMonitor`, so **no library scan is needed**
- **Freshness**: a separate weekly timer runs `yt-dlp -U`. Extractor staleness is the main failure mode; yt-dlp itself warns once a build is 90 days old

### The units must be copied, not symlinked

These were originally symlinked out of `sys/t1/` into `/etc/systemd/system/`, and
that silently broke at the next reboot for the same reason `t1-metrics.service`
did — this repo lives under `/home`, which is not mounted when systemd loads
units:

```
yt-queue.timer: Failed to open /etc/systemd/system/yt-queue.timer: No such file or directory
yt-dlp-update.timer: Failed to open /etc/systemd/system/yt-dlp-update.timer: No such file or directory
```

The timers reported `enabled` and `LoadState=loaded` afterwards, because by the
time anything asked, `/home` was mounted and the file was readable again. But
`Active: inactive (dead)`, `Trigger: n/a`, and `systemctl list-timers` showed no
NEXT — the boot-time start had already failed. Downloads simply stopped, with
nothing to say so.

Fix, remembering the `*.wants/` symlink is the one systemd actually reads at boot:

```bash
sudo install -m644 sys/t1/yt-queue.service sys/t1/yt-queue.timer \
  sys/t1/yt-dlp-update.service sys/t1/yt-dlp-update.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl reenable yt-queue.timer yt-dlp-update.timer
sudo systemctl start yt-queue.timer yt-dlp-update.timer
```

The explicit `start` is not redundant. `--now` means *try-restart* when paired
with `reenable`, and try-restart is a no-op on a stopped unit — it exits `success`
and starts nothing, which looks identical to having worked. The metrics recipe
above gets away with `reenable --now` only because that service is long-running
and was already active at the time.

Verify a NEXT time actually appears, which is the part `is-enabled` will not tell
you:

```bash
systemctl list-timers yt-queue.timer yt-dlp-update.timer
ls -l /etc/systemd/system/timers.target.wants/
```

`yt-posters.sh` stays in the repo — like `t1-metrics.py` it is read at service
*start*, long after `/home` is mounted.

### Why not Watch Later

Watch Later is a **system-managed playlist**. The Data API allows `list` and `insert` but blocks `update` and `delete`, so items cannot be removed programmatically — only browser automation or the undocumented internal endpoint can do it. An ordinary unlisted playlist avoids this, and has a second benefit that matters more: **unlisted is readable anonymously**, so no `cookies.txt` is involved and there is nothing to rotate or refresh.

Removal was dropped entirely rather than worked around. The download archive already guarantees nothing downloads twice, so draining the playlist would have been cosmetic — and it was the only part requiring an OAuth client and a stored refresh token.

### Notes

- **`~/.config/yt-dlp/config` must not be edited to suit this host.** Its `--output` is `/downloads/%(uploader)s/...`, an absolute path that only makes sense inside the container the `yt-dlp` fish function runs, which bind-mounts `$PWD` onto `/downloads`. There is no `/downloads` on t1. That config is shared with other machines still using the fish function, so the units pass `-P` and `-o` on the command line instead — yt-dlp treats config-file options as if they preceded command-line ones, so the command line wins.
- **`%` must be doubled in the unit.** systemd reads `%` as its own specifier prefix, so yt-dlp's `%(uploader)s` template is written `%%(uploader)s`. Without this the unit fails to start.
- **`-P temp:` keeps partial files out of the library.** Fragments and `.part` files go to `/mnt/aux/yt-queue/tmp`, so Jellyfin's realtime monitor never sees a half-written file appear and disappear.
- **`--no-write-playlist-metafiles` is required**, because writing them is yt-dlp's default. Otherwise the playlist's own `info.json` and thumbnail are written as though the playlist were a video, creating a phantom directory in the library named after the account, holding metadata and no media. Jellyfin surfaces that as a bogus series.
- **PO tokens come from the `bgutil-pot` container**, bound to `127.0.0.1:4416`, via the plugin at `~/.config/yt-dlp/plugins/`. The unit is `After=docker.service` but not `Requires=` — if the provider is down the run fails and simply retries next hour. `[pot:bgutil:http] Generating a gvs PO Token` in the journal confirms the chain is live.
- **The service runs as `deity`**, which is what makes `~/.config/yt-dlp/{config,plugins}` discoverable at all; as root it would silently read a different config and no plugins.
- **`DENO_DIR` and `--cache-dir` are redirected onto `/mnt/aux`.** Deno solves YouTube's JS challenges and yt-dlp caches nsig signatures; both default to writing under `$HOME`, which `ProtectHome=read-only` forbids. Redirecting them is what lets the home directory stay read-only.
- **`yt-dlp-update.service` deliberately omits `ProtectHome`**, unlike every other unit here — it is the one service that must write to `/home`, and `ReadWritePaths=/home/deity/.local/bin` is its only writable path.
- **Long downloads cannot stack.** systemd will not run two copies of a `oneshot` in parallel; a trigger arriving mid-download merges into the running job.
- **Subtitles are deliberately off**, and the shared config's `--write-subs`/`--embed-subs` are negated in the unit rather than removed from that file, which other machines still use. If they are ever wanted, note that `--sub-langs` values are **regexes** and must be exact: `"en.*"` looks reasonable and is a disaster, because YouTube exposes auto-translated tracks as `en-ar`, `en-zh-CN`, `en-de-DE` and dozens more. It matched all of them, fired ~50 subtitle requests per video, and earned an HTTP 429 that aborted the video outright. Use `"en"`, plus `--write-auto-subs` — most YouTube videos carry only auto-generated captions, so `--write-subs` alone produces nothing.

### Metadata and artwork

Metadata comes from the `.info.json` files yt-dlp writes alongside each video, read by the YoutubeMetadata plugin's **local** provider. The plugin's **remote** provider is deliberately disabled.

| Layer | Source |
| --- | --- |
| Episode metadata | local `.info.json`, via the plugin's local reader |
| Episode thumbnail | embedded in the file by `--embed-thumbnail` |
| Channel artwork | `poster.jpg` per channel directory, from `sys/t1/yt-posters.sh` |

The remote provider is disabled because it cannot work here: it calls `new YoutubeDLP()` with no path, so NYoutubeDL scans `PATH` for a binary named literally `youtube-dl` — dead upstream and absent from the container. `PluginConfiguration.cs` exposes only an `IDType` enum, so there is **no setting to point it at yt-dlp**. Making it work would mean a `DOCKER_MODS` package install plus a `custom-cont-init.d` symlink, giving a second yt-dlp inside the container with no PO token provider, while the host already runs one that has `bgutil-pot` wired up. It was left failing for days, logging 250 errors a day, and cost nothing — every episode already had metadata and a thumbnail without it.

`yt-posters.sh` runs as `ExecStartPost` on `yt-queue.service`. It derives each channel's URL from the `channel_url` field already present in any video's `.info.json`, so there is no list of channels to maintain, and skips any directory that already has a poster. `--playlist-items 0` fetches the channel's own thumbnail without touching a video.

- **The library config is Jellyfin runtime state, not in this repo.** It lives in `~/srv/jellyfin/data/root/default/YouTube/options.xml`. `YoutubeMetadata` was removed from `MetadataFetchers` and `ImageFetchers` for both Series and Episode; it stays in `LocalMetadataReaderOrder`, which is the local path and the thing actually doing the work. The `*Order` lists are only ordering and were left alone. A backup sits beside the file.
- **Retiring the remote provider also disables manual "Identify" search** in the Jellyfin UI. Filenames carry `[videoid]` and the local reader keys off exactly that, so nothing routine depends on it.
- **Jellyfin picked the posters up without a library scan**, on restart alone.

### Optional one-liners

Each is a flag on `ExecStart`, deliberately left off:

| Want | Add |
| --- | --- |
| Strip sponsor segments | `--sponsorblock-remove sponsor,intro,outro` — **destructive**, cuts the media; `--sponsorblock-mark` only writes chapters |
| Cap bandwidth | `--limit-rate 50M` |
| Cap resolution | `-S "res:1080"` |

### Pinchflat

Considered and rejected. It is the right shape — one container, yt-dlp, Jellyfin-correct naming — but the maintainer opened *"READ: Temporary Development Pause"* (issue #800) on 2025-09-26 saying 4–8 weeks minimum, and there has been no release since that day and no code push since 2025-12-16, against 213 open issues trending toward operational rot. It also bundles its own yt-dlp and Deno POT provider, duplicating two things this host already runs. Files land in its expected layout anyway, so adopting it later costs nothing.

## Xbox One S Controller (Bluetooth)

Controller: 045E:02FD (Model 1708). Works with the kernel's built-in `hid-microsoft` driver — no extra packages needed.

### Pairing

```bash
bluetoothctl scan on
# hold pair button on controller
bluetoothctl pair 5C:BA:37:26:8A:CD
bluetoothctl trust 5C:BA:37:26:8A:CD
bluetoothctl connect 5C:BA:37:26:8A:CD
```

The controller can sometimes send a corrupted HID descriptor over Bluetooth (`parse failed` in dmesg). This is transient — remove and re-pair to fix:

```bash
bluetoothctl remove 5C:BA:37:26:8A:CD
# power cycle controller, then re-pair from scratch
```

Verify: `journalctl -b -g 045e` should show "gamepad detected" not "parse failed".

### Steam

Enable "Xbox Configuration Support" in Steam Settings → Controller.

## Bulk Storage on /mnt/aux

Secondary 2 TB NVMe (`/dev/nvme0n1p1`, btrfs+zstd) holds bulky replaceable data. Mounted via fstab so symlinks survive reboots.

```
# /etc/fstab
UUID=7321bcf0-fe6d-4899-8108-a4dde896910d /mnt/aux btrfs defaults,compress=zstd:3,ssd 0 2
```

Symlinks from `~`:

```bash
ln -s /mnt/aux/games     ~/games
ln -s /mnt/aux/media     ~/media
ln -s /mnt/aux/downloads ~/downloads
```

To move a directory across:

```bash
mv ~/somedir /mnt/aux/somedir
ln -s /mnt/aux/somedir ~/somedir
```

After moving, root space won't fully free until btrfs snapshots holding the old data rotate out. `/mnt/aux` is **not** covered by `omarchy-snapshot` and does not inherit root's protections — only put replaceable data here (game installs, media, downloads). Anything that matters belongs on root.

## HDMI Dropouts on AMD iGPU (historical)

**Not current.** The display now hangs off the RTX 5090 (see *Sunshine*), so none of this
applies as written — kept because it bites again if the cable ever moves back.

The card number below is whatever the iGPU enumerates as; it is not stable across boots.

With the display on the motherboard HDMI (AMD iGPU) to save ~500MB VRAM for ComfyUI, the
2880x1800@100Hz mode needs a 563 MHz TMDS pixel clock, which is near the 600 MHz max and above the 340 MHz scrambling threshold. The iGPU's aggressive power management in `auto` mode can cause intermittent HDMI link drops (visible as brief screen blackouts and `Connector HDMI-A-2 disconnected` in the Hyprland log).

Fix: lock the iGPU out of deep power saving states:

```bash
echo low | sudo tee /sys/class/drm/card2/device/power_dpm_force_performance_level
```

Persistence via udev rule:

```
# /etc/udev/rules.d/99-amdgpu-dpm.rules
ACTION=="add", SUBSYSTEM=="pci", DRIVERS=="amdgpu", ATTR{power_dpm_force_performance_level}="low"
```

If dropouts persist, lower the refresh rate to 60Hz (pixel clock drops to ~340 MHz):

```
# ~/.config/hypr/monitors.conf
monitor = HDMI-A-2,2880x1800@60,0x0,2
```

## UPERFECT EDID HDR Strip (NVIDIA HDMI-A-1)

The UPERFECT UColor O2 advertises HDR (PQ EOTF) over HDMI. Steam Big Picture inside gamescope auto-enables HDR if the panel reports support, which triggers NVIDIA bug #5240452 at >2560x1440@120 — bottom of the screen renders as garbage. Disabling HDR on the monitor doesn't help because gamescope still signals BT.2020/HDR_OUTPUT_METADATA at the DRM level; the panel then receives BT.2020-encoded pixels and treats them as sRGB → washed-out colors. No gamescope CLI flag suppresses the HDR path on NVIDIA.

Fix: strip the HDR Static Metadata block from the panel EDID at the kernel level so the panel "no longer" advertises HDR. gamescope's auto-enable can't fire and the entire HDR signalling chain is skipped.

The EDID's CEA-861 extension block has the HDR Static Metadata DBC tag at bytes 175–181 (`e6 06 05 01 62 62 00`). Byte 177 is the EOTF bitmap — bit 0 = SDR gamma, bit 2 = PQ HDR. Clear bit 2 (`0x05` → `0x01`), then recompute the extension-block checksum at byte 255 (sum of bytes 128–254 plus checksum must be 0 mod 256, so `0x5f` → `0x63`).

```python
# generate /lib/firmware/edid/uperfect-sdr.bin
import pathlib
b = bytearray(pathlib.Path('/sys/class/drm/card1-HDMI-A-1/edid').read_bytes())
b[177] = 0x01
b[255] = (-sum(b[128:255])) & 0xff
pathlib.Path('uperfect-sdr.bin').write_bytes(bytes(b))
```

Install and wire into the boot path:

```bash
sudo install -Dm0644 uperfect-sdr.bin /lib/firmware/edid/uperfect-sdr.bin
echo 'FILES+=(/lib/firmware/edid/uperfect-sdr.bin)' | sudo tee /etc/mkinitcpio.conf.d/edid-uperfect.conf
```

Add to `KERNEL_CMDLINE` in `/etc/default/limine`:

```
KERNEL_CMDLINE[default]+=" drm.edid_firmware=HDMI-A-1:edid/uperfect-sdr.bin"
```

```bash
sudo limine-mkinitcpio
sudo reboot
```

Verify:

```bash
od -An -tx1 -v /sys/class/drm/card1-HDMI-A-1/edid | awk 'NR==12 {print "byte 177 =", $2}'
# want: byte 177 = 01
```

The blob must be in initramfs (not just rootfs) because nvidia-drm probes connectors during early KMS, before the rootfs firmware tree is mounted. Confirm with `sudo lsinitcpio /boot/EFI/Linux/omarchy_linux.efi | grep edid`.
