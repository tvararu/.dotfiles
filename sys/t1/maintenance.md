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
  which silently breaks the auth of anything that reads them. `name: t1` in
  the file pins the project name regardless of where it is invoked.

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

**Ordering alone is not enough.** `tailscaled` is `Type=notify` and signals
readiness when its daemon and local API are up, not when `tailscale0` has an
address. Docker starts into that gap. The 2026-08-26 boot:

```
08:50:27  tailscaled active (notify ready)
08:50:28  llama-qwen38 starts -> docker-proxy fails to bind 100.73.138.96:8001
08:50:30  docker active
```

The container ran `healthy` with no published port for a day. Its healthcheck
curls itself from inside the namespace, so nothing reported it. Symptoms:

```bash
docker port <container>            # silent = nothing published
ss -ltn | grep <port>              # no listener
docker inspect <c> -f '{{json .NetworkSettings.Ports}}'   # {}
```

**Do not bind published ports to a Tailscale IP.** Publish to `127.0.0.1` and
proxy it with `tailscale serve`. Loopback exists at container start, so the race
cannot happen.

No Docker container binds `100.73.138.96` as of 2026-08-27. Native ollama still
does, because Serve cannot proxy it. It survives the race by retrying instead.
See *Ollama (native)*.

### Tailscale accepts inbound before ufw sees it

`tailscaled` installs its own `ts-input` chain that ACCEPTs traffic arriving on
`tailscale0` for this node, ahead of ufw's default-deny. **Every host-bound
service is reachable from the tailnet with no ufw rule at all.** `8123` (Home
Assistant) has no `allow` rule, and still answers over the tailnet.

So **ufw here governs LAN and WAN exposure only.** Tightening a ufw rule does not
reduce what the tailnet can reach. Device membership gates that. One exception,
below.

### Service VIPs: declare ports as `tcp:443`, not `443`

A Tailscale Service definition's `ports` **must carry the protocol prefix**. Created
with `["443"]`, the control plane never validates the host as actually serving it,
so it never publishes the service VIPs into that host's `AllowedIPs`. Peers then
have no route to the VIP, every SYN dies on the client, and the connection hangs to
timeout with no refusal and nothing logged anywhere.

```bash
curl -u "$TS_API_KEY:" -X PUT -H 'Content-Type: application/json' \
  -d '{"name":"svc:x","addrs":["<v4>","<v6>"],"ports":["tcp:443"],"comment":"..."}' \
  https://api.tailscale.com/api/v2/tailnet/-/vip-services/svc:x
```

`addrs` must be present on update (both families) or it 400s on that before it ever
looks at `ports` — which makes a wrong `ports` value easy to misread as rejected.

**Diagnose from a second node, never the host.** The host short-circuits its own
service VIP in-process, so it returns a healthy 200 while every peer times out —
a false positive that wasted most of an evening here. On a peer:

```bash
tailscale ping <VIP>                 # "no matching peer" = VIP not published
tailscale debug netmap | grep -A2 't1\.'   # AllowedIPs should list the VIP pairs
```

Fixed 2026-08-27. The tell is `AllowedIPs` on the host peer: with the bad format it
holds only the node's own addresses, and gaining the VIP pairs is the moment it
starts working.

**On ufw.** A `ufw allow in on tailscale0 to any port 443 proto tcp` rule was added
while chasing this, and is still in place. It is probably **not** required: Tailscale
intercepts inbound TCP to a *served* VIP port inside netstack, before kernel
netfilter sees it. Traffic to a VIP port that is *not* served does fall through to
the host. Removing the rule is untested — verify from a peer before concluding
either way.

### Containers resolve DNS through the host

`/etc/systemd/resolved.conf.d/20-docker-dns.conf` puts a systemd-resolved stub
listener on the docker0 bridge:

```ini
[Resolve]
DNSStubListenerExtra=172.17.0.1
```

Containers then use `172.17.0.1:53`, which is why ufw carries
`allow proto udp to 172.17.0.1 port 53 from 172.16.0.0/12` — that range covers
both `docker0` (172.17) and the compose network (172.20). **This file is a system
drop-in, not stowed from here**; it is recorded because nothing else does.

ufw also carried the same allow from `192.168.0.0/16`, which let any LAN host use
this box as a resolver. Audited 2026-08-28 and no consumer found — no libvirt
networks, no VM images, no container subnet on `192.168.x`. Only the `172.16.0.0/12`
rule is needed. If it turns out something did want it, the symptom is specific:
containers resolve fine and something on the LAN stops resolving.

### Docker published ports over Tailscale (ufw-docker)

The ufw-docker ruleset (in `/etc/ufw/after.rules`) only allows RFC1918 LAN
sources through to Docker-published ports; Tailscale sources are CGNAT
(`100.64.0.0/10`), so their SYNs are silently dropped in `DOCKER-USER`
(`[UFW DOCKER BLOCK]` in kernel log). Host-bound services (INPUT path, e.g.
ollama on the tailscale IP) are unaffected — only the FORWARD/DNAT path
to containers is filtered. Symptom: connection *timeout* from tailnet peers
while closed ports get *refused*.

Allow per-port with `ufw route allow` (checked before the drop rules):

```bash
sudo ufw route allow proto tcp from 100.64.0.0/10 to any port 3724 comment 'wow auth from tailnet'
sudo ufw route allow proto tcp from 100.64.0.0/10 to any port 8085 comment 'wow world from tailnet'
sudo ufw route allow proto tcp from 100.64.0.0/10 to any port 8888 comment 'playerbots tcp from tailnet'
```

Affected here, verified 2026-08-27 from a second tailnet node — this is the only
Docker-published port left on the box, so it is the only one blocked:

| Port | Service  |
| ---- | -------- |
| 8096 | jellyfin |

8188 left this list when ComfyUI moved behind `comfyui-proxy.socket`, and 8675
when aitoolkit moved to a loopback publish behind Serve. Both take the INPUT path
now and are no longer filtered here — see "Port 8188 moved off the Docker path"
under ComfyUI. That is the general escape from this problem for an HTTP service,
alongside `tailscale serve` below.

Everything else is `network_mode: host`. Jellyfin is the one that still works
over the LAN, which is what the RFC1918 allowance covers. The three `ufw route
allow` rules above are currently inert — no AzerothCore containers are running
— as is the `27036` Steam rule.

#### Tailscale Serve, which needs no firewall rule

For an HTTP service, `tailscale serve` avoids the problem. `tailscaled` dials
`127.0.0.1:<port>` from the host, so the connection is locally generated and
never enters `FORWARD`/`DOCKER-USER`.

```bash
tailscale serve --bg 8096          # https://t1.gentoo-bangus.ts.net/ -> 127.0.0.1:8096
tailscale serve status
tailscale serve --https=443 off    # disable
```

Jellyfin uses it, configured 2026-08-27 after tailnet peers were dropped in
`DOCKER-USER`. Jellyfin holds `/` on `:443`, so each further backend takes its own
HTTPS port — aitoolkit on `8675`, ComfyUI on `8188`. One cert covers every port.
`--set-path` is the alternative, but Serve strips the prefix before forwarding, so
a backend that has its own URL prefix will 404 on its assets.

No sudo, no ufw change, real Let's Encrypt cert. The config lives in
`/var/lib/tailscale/tailscaled.state` and survives reboots, but not
`tailscale logout` or a state wipe.

**Serve forwards the original `Host` header.** A backend that validates `Host`
against an allowlist rejects everything proxied through it. ollama returns a bare
403 this way — see *Ollama (native)*. Check before assuming Serve is a drop-in.

Trade-offs. The stream goes through tailscaled rather than direct. The client
URL becomes the MagicDNS name. It covers HTTP only — raw TCP needs `--tcp` or a
`ufw route allow`. Whether `http://t1:<port>` still works on the LAN depends on
the container's own bind, not on Serve. Jellyfin still publishes `0.0.0.0:8096`,
so `http://t1:8096` is unchanged.

The HTTPS is incidental. Tailscale is WireGuard, so the transport is already
encrypted and the peer authenticated by public key. TLS on top matters only for
browser secure-context features (PWA install, service workers), which the iOS
Jellyfin app does not use.

#### Tailscale Services, for URLs with no port

Serve puts each extra backend on its own port. A **Service** instead gives each
one its own MagicDNS name and virtual IP, all on 443 —
`https://jellyfin.gentoo-bangus.ts.net/`. Set up 2026-08-27. Four things that are
easy to get wrong, in the order they bite:

- **The host needs a tag-based identity.** Converted with
  `sudo tailscale up --advertise-tags=tag:server --advertise-exit-node --operator=deity`;
  `up` refuses unless every non-default flag is restated. Tagging costs Taildrop
  and Tailscale SSH to user-owned nodes. A tagged node also leaves
  `autogroup:member`, so any `nodeAttrs` granting it something (`funnel` here)
  must name `tag:server` explicitly or it silently loses it.
- **The Service must exist before a host advertises it.** Advertise first and the
  CLI reports "approval from an admin is required" indefinitely, with nothing in
  the console to approve. Create it in the admin console, or by API:

```bash
curl -u "$TS_API_KEY:" -X PUT -H 'Content-Type: application/json' \
  -d '{"name":"svc:jellyfin","ports":["tcp:443"],"comment":"Jellyfin on t1"}' \
  https://api.tailscale.com/api/v2/tailnet/-/vip-services/svc:jellyfin
```

`tcp:443`, **not** `443` — a bare port silently stops the service ever working.
See *Service VIPs* under the ufw section.

- **Host approval is not exposed in the REST API** — `/hosts` and `/approve` both
  404. Click it in the console, or let the policy file do it. Each Service also
  needs a `grants` entry; the legacy `acls` allow-all does **not** cover `svc:`
  destinations.

```json
"autoApprovers": { "services": { "svc:jellyfin": ["tag:server"] } },
```

- **`tailscale serve advertise` registers the host without the port config.** The
  console then says "Advertising the service, but some required ports are
  missing". Re-run the full line instead — it does both:

```bash
tailscale serve --service=svc:jellyfin --bg --https=443 127.0.0.1:8096
```

Node-level Serve entries and Service entries coexist; the old
`t1.gentoo-bangus.ts.net:<port>` URLs keep working alongside the new names.

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

### Idle VRAM reclaim

Sunshine creates a CUDA context during its **startup** encoder probe and holds it
for the life of the process, connected or not. Measured on 2026-08-27:

| State | Sunshine VRAM |
| --- | --- |
| Idle | 513 MiB |
| Streaming | 592 MiB |

The stream itself costs 79 MiB. The other 513 MiB is idle overhead, which matters
because `llama-server` routinely holds ~29 GB of the 5090's 32 GB and leaves
about 2 GB free. The +79 MiB is released correctly on disconnect, so there is no
leak across sessions — [Sunshine#1060](https://github.com/LizardByte/Sunshine/issues/1060)
does not apply at this version. Nothing in the config releases the idle context.
Stopping the process is the only way to get it back.

A oneshot plus timer does that: `sunshine-idle-stop.{service,timer}`, driven by
`sunshine-idle-stop.sh`.

**The stream probe is `ss -lnup | grep '"sunshine"'`.** Sunshine binds UDP
47998-48000 (control, audio, video) when a session starts and closes them
immediately on disconnect; it holds no UDP socket while idle. Verified in both
directions against a live stream. The TCP ports 47984/47989/47990/48010 stay
bound the whole time and are useless as a probe.

The script clamps measured idle time to the unit's own uptime. Without that, a
stamp file left over from a previous Sunshine process would stop a freshly
started one on the next tick.

These are **user** units, not system units, because Sunshine itself is one. They
install to `~/.config/systemd/user/`, no `sudo`:

```bash
install -m644 sys/t1/sunshine-idle-stop.service sys/t1/sunshine-idle-stop.timer \
  ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user reenable sunshine-idle-stop.timer
systemctl --user start sunshine-idle-stop.timer
systemctl --user list-timers sunshine-idle-stop.timer
```

The `/home` hazard that forces system units into `/etc/systemd/system/` does not
apply here: the user manager starts after login, long after `/home` is mounted.
Copies rather than symlinks anyway, to match the rest of this repo.

Sunshine stops between 60 and 65 minutes after the last disconnect (`IDLE_SECS`
in the service, 5-minute tick in the timer). It still autostarts at login through
`WantedBy=graphical-session.target`, then stops itself an hour later if unused.
`systemctl --user disable app-dev.lizardbyte.app.Sunshine.service` for a cold
default instead. Start it again before streaming with the `start-sunshine` fish
function, which runs from any machine:

```bash
start-sunshine
```

It pipes one `sh` snippet over `ssh t1` rather than making several ssh calls, so
the readiness wait costs one round trip. It is idempotent — repeat calls report
`Sunshine is already running` and exit 0 — and it waits for port 47989 to open
before returning, so Moonlight finds the host on its first poll rather than
showing it offline. Cold start measures about 6 s, 5 s of which is the
`ExecStartPre=/bin/sleep 5` in the packaged unit. On t1 it skips the ssh hop.

`systemctl --user` over ssh depends on `XDG_RUNTIME_DIR`, which `pam_systemd`
sets on login (it is in sshd's stack via `system-remote-login` → `system-login`)
and `loginctl enable-linger` keeps `user@1000.service` alive without a session.
The function sets the variable itself anyway, so it does not depend on the PAM
stack staying as it is.

### Why not socket activation

Starting Sunshine on the first Moonlight poll was considered and rejected.
Sunshine exports no socket-activation symbols:

```bash
nm -D /usr/bin/sunshine | grep sd_listen   # no output
```

So it cannot accept file descriptors from systemd, and `systemd-socket-proxyd`
— the usual workaround — proxies TCP only, while Sunshine needs UDP for video,
audio, and control. `bind_address` does not rescue it: binding to localhost would
break the UDP path too.

What would work is a trigger socket on 47989 that releases the port before
Sunshine starts (`ExecStartPre=systemctl --user stop sunshine-trigger.socket`,
re-armed by `ExecStopPost=`). The triggering connection is dropped, so Moonlight
shows the host offline for one poll and finds it ~10 s later on a retry, and mDNS
discovery is dead while Sunshine is down. Not worth it for 513 MiB. Note that
Sunshine re-probes all three encoders at every connect anyway, so a cold start
adds process startup only, not probe time.

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

The only local inference stack on t1 since 2026-08-27. Native systemd service:
direct CUDA on the RTX 5090, journald logs, no container. Replaced the llama.cpp
compose profiles (`qwen38`, `a3b`, `qwopus`), removed the same day.

Two reasons. It unloads idle models, returning **~29-30 GB** of VRAM at 262144
with q8_0 KV. The llama.cpp container held its allocation permanently. It also
benchmarked faster on the same model, though see the caveat on that comparison
below.

```bash
yay -S --needed ollama-cuda
```

The package creates the `ollama` user and `/var/lib/ollama` (700, `ollama:ollama`).
The unit sets `OLLAMA_MODELS=/var/lib/ollama`.

### Configuration

Fish has no heredoc and fails with `Expected a string, but found a redirection`.
In fish, use `printf`:

```fish
printf '%s\n' '[Unit]' 'After=tailscaled.service' 'Wants=tailscaled.service' '' \
  '[Service]' 'Environment="OLLAMA_HOST=100.73.138.96:11434"' \
  'Environment="OLLAMA_KEEP_ALIVE=2h"' 'Environment="OLLAMA_FLASH_ATTENTION=1"' \
  'Environment="OLLAMA_KV_CACHE_TYPE=q8_0"' \
  'Environment="OLLAMA_CONTEXT_LENGTH=262144"' \
  'RestartPreventExitStatus=' 'Restart=on-failure' 'RestartSec=5' \
  | sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null
```

The same thing as a bash heredoc:

```bash
sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null <<'EOF'
[Unit]
After=tailscaled.service
Wants=tailscaled.service

[Service]
Environment="OLLAMA_HOST=100.73.138.96:11434"
# 2h, not the 5m default: the prompt cache lives in the llama-server heap and
# dies with the process, so an idle unload costs a full cold reprocess of the
# whole conversation. At 262144 that is minutes. Holds ~30 GB for 2h after last
# use, which will block ComfyUI from loading.
Environment="OLLAMA_KEEP_ALIVE=2h"
# Without these ollama picks 32768 from free VRAM. See Context length below.
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_KV_CACHE_TYPE=q8_0"
Environment="OLLAMA_CONTEXT_LENGTH=262144"
# Arch's unit sets RestartPreventExitStatus=1 and ollama exits 1 when its bind
# address does not exist yet. Clearing it lets the boot race self-heal.
RestartPreventExitStatus=
Restart=on-failure
RestartSec=5
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now ollama
```

Reachable from the tailnet at `http://t1:11434` or `http://100.73.138.96:11434`.
LAN clients get connection refused at bind level, so no ufw rule applies.

**The CLI needs `OLLAMA_HOST` set, even on t1.** It defaults to
`127.0.0.1:11434` while the server binds the tailnet IP. A bare `ollama ps` then
fails with `could not connect to ollama server`. `fish/config.fish` exports it:

```fish
test (hostname) = t1; and set -x OLLAMA_HOST t1:11434
```

#### Why it binds the Tailscale IP rather than loopback + Serve

aitoolkit and ComfyUI bind `127.0.0.1` behind `tailscale serve`, as of
2026-08-27. **ollama cannot use that pattern.** It validates `Host` against an
allowlist: `localhost`, loopback literals, and the machine hostname. Serve
forwards `Host: t1.gentoo-bangus.ts.net:8443`, which is not on that list.
Proxied requests return 403 with an empty body. Verified 2026-08-27:

```bash
curl -o /dev/null -w '%{http_code}\n' -H 'Host: t1' http://127.0.0.1:11434/v1/models          # 200
curl -o /dev/null -w '%{http_code}\n' -H 'Host: t1.gentoo-bangus.ts.net:8443' http://127.0.0.1:11434/v1/models  # 403
```

`OLLAMA_ORIGINS` does not govern this. It feeds gin's CORS middleware, and bare
hostnames panic the server at startup (`bad origin: origins must contain '*' or
include http://,https://,...`). No allowed-hosts knob exists in 0.32.15.

The boot race is handled by retry instead. `After=tailscaled.service` is not
enough on its own, for the reason in *Docker: start after Tailscale*. Clearing
`RestartPreventExitStatus` is what makes it recover. Before that, ollama failed
at every boot in the journal with `bind: cannot assign requested address` and
`NRestarts=0`.

#### Context length

ollama does not read the model's trained context. It picks one of three tiers
from free VRAM at load time, documented in its help as `4k/32k/256k based on
VRAM`. With `OLLAMA_CONTEXT_LENGTH` unset it chose **32768**, against a trained
window of 262144 (`qwen35.context_length` in `ollama show`).

f16 KV is why. Measured on t1, f16 costs ~70 KiB/token. The reason is
architectural: `qwen35.full_attention_interval = 4`, so **only 16 of 64 layers
carry a KV cache** and the other 48 are gated-DeltaNet with a fixed 748 MiB
recurrent state. 16 x 2 x 4 heads x 256 dim x 2 B = 64 KiB, plus 4 KiB for the
MTP draft cache. A genuinely dense 27B with these head dimensions would cost
256 KiB/token, so long context is affordable here only because of the hybrid:

| Context | f16 KV | Total VRAM |
|---|---|---|
| 32768 | — | 21569 MiB |
| 65536 | +2210 MiB | 23779 MiB |
| 131072 | +4480 MiB | 28259 MiB |
| 262144 | — | ~37 GB, does not fit |

Quantised KV recovers the full window. It needs flash attention. Both configs
below load 100 % on GPU at 262144, verified 2026-08-27:

| KV type | Context | VRAM | structured | prose |
|---|---|---|---|---|
| f16 | 32768 | 21569 MiB | 182.60 | 120.12 |
| q8_0 | 262144 | 30527 MiB | 173.69 | 113.03 |
| **q4_0** | **262144** | **26425 MiB** | **172.64** | **111.55** |

`q8_0` is in use. Better KV precision is what long context is for, and `q4_0`
loses precisely there. On **decode throughput** the two are level: `q4_0` is
0.60 % behind on structured output and 1.31 % behind on prose. Full context costs
about 5 % of decode speed and 4.9 GB of VRAM against the 32768 default. Part of
that 5 % is disk contention from a concurrent download, so the real cost is
lower.

`q8_0` leaves 1615 MiB spare. Nothing on this box competes for it: t1 runs
headless, and the ~1 GB in use is Sunshine (513 MiB, only while streaming), the
metrics publisher (498 MiB) and walker (51 MiB).

The one failure to know about. ollama measures free VRAM at load and splits
layers between GPU and CPU to fit. With the context pinned it cannot shrink the
window to compensate, so it offloads layers instead — a large slowdown with no
error. If something ever does hold VRAM at load time, `ollama ps` shows a
`PROCESSOR` other than `100% GPU`. `q4_0` leaves 5717 MiB and always loads
whole.

262144 is the ceiling. It is the model's trained window, and ollama exposes no
rope-scaling option to go past it.

Add to the drop-in:

```
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_KV_CACHE_TYPE=q8_0"
Environment="OLLAMA_CONTEXT_LENGTH=262144"
```

**Those percentages are speed only. No quality comparison was made between the
two cache types, and accuracy is where they actually differ.** A 4-bit KV cache
holds every past token at lower precision than an 8-bit one, and the loss
compounds as the context fills. The benchmark generated 400 tokens from short
prompts, so it never filled the cache and cannot detect this. llama.cpp ran
`q4_0` here for months, so the risk is not new, but it is unquantified.

#### What the 262144 window actually costs

Measured 2026-08-27 at depth 3, real Python source as filler, a unique nonce per
request so prefix matching fails and the whole prompt is reprocessed. Medians,
5 repeats to 64k and 3 above.

| prompt tokens | time to first token | prefill tok/s | decode tok/s |
|---|---|---|---|
| 1,059 | 0.44 s | 2751 | 145.6 |
| 8,725 | 3.00 s | 3006 | 134.4 |
| 32,462 | 12.03 s | 2755 | 130.3 |
| 64,512 | 29.18 s | 2250 | 108.8 |
| 128,897 | 83.50 s | 1562 | 86.4 |
| 205,741 | 178.62 s | 1156 | 60.0 |

**Measured at the old 500 W cap.** The cap is now 575 W, worth +6% decode and
+8% prefill, so these figures are that much pessimistic. See "Power cap
500 → 575 W" below.

Prefill and decode both fall to about 42% of their 1k rate by 200k, almost in
lockstep. Time to first token is strongly superlinear: 1.6x the tokens from 128k
to 200k costs 2.1x the wait.

**Those are cold numbers and most turns are not cold.** Each request above was
nonce-prefixed so prefix matching failed and the whole prompt reprocessed. A
conversation that grows naturally reuses its prefix instead. Measured on live
agent traffic, 102 turns at ~27k context:

```
selected slot by LCP similarity, f_sim_best = 0.979   (91/102 above 0.9, none below 0.2)
restored context checkpoint (n_past = 27044, size = 255.783 MiB)
prompt eval time = 265.54 ms / 449 tokens
```

Only the new tokens are prefilled — 96 to 2493 per turn rather than 27,000 — so
an incremental turn costs a few hundred milliseconds, not the cold figure.

**The cold cost is what you pay on a cache miss**, and the misses that matter
are:

- **the model unloading.** The prompt cache lives in the `llama-server` heap and
  dies with the process, so on the 5m default a coffee break mid-session costs a
  full reprocess — 84 s at 128k, three minutes at 200k. This is why keep-alive
  is 2h
- **anything changing at the front of the prompt**, which invalidates everything
  after it. ollama 0.33.0 fixed one such case where Claude Code's token-countdown
  system message was being relocated to the prompt head, busting the cache on
  every request
- **slot contention** between interleaved clients, since `-np 1` means one slot
- **checkpoint invalidation** — 674 `erased invalidated context checkpoint`
  events in one day, the bug 0.33.1 addresses

**Decode degradation is not cacheable.** 145.6 tok/s at 1k, 86.4 at 128k, 60.0
at 200k is a function of KV depth, so it applies to every turn however warm the
cache is. A long session generates more slowly even when it never reprocesses.

**Do not cap client context to avoid these costs.** 262144 is the working
window and anything under 128k is not useful for the agent work this box exists
for. A client-side cap saves nothing anyway — the server allocates the full KV
upfront regardless — and it forces earlier compaction, which rewrites the prompt
front, invalidates the prefix cache and buys a full cold reprocess. A lower cap
is therefore a way to pay the cold cost *more* often, not less.

The costs above are real, so treat them as things to mitigate rather than avoid:

- keep the model hot, so the cache survives between turns
- take ollama 0.33.1 for the recurrent-layer prefill fix
- expect ~60 tok/s decode at the top of the window; that part is not fixable
  here

#### Long prompts can abort the server

At 64k, one request in roughly ten kills `llama-server` outright:

```
ggml-cuda.cu:106: CUDA error
CUDA error: the launch timed out and was terminated
  in function ggml_backend_cuda_synchronize
llama-server terminated  error="signal: aborted (core dumped)"
```

Backtrace frame 14 is `server_context_impl::update_slots()`. This is CUDA error
702, the driver watchdog, which is armed because this card also drives a
display. **Every in-flight request dies with the process**, surfacing as an
HTTP 500, so this is an availability limit and not only a latency one.

It is intermittent rather than a ceiling — 128k and 200k have each run clean
three times since. The journal immediately before the abort is full of
`erased invalidated context checkpoint`, and ollama 0.33.1's release note
describes exactly that machinery recording "restore points that fail to cover
what they claim" on recurrent-layer models. Qwen3.8 is one:
`full_attention_interval = 4` puts 48 of its 64 layers on gated-DeltaNet.
Suggestive, not proven — a watchdog timeout is also explainable by recurrent
kernels simply running long. Re-test after upgrading.

#### Idle unloading

`ollama ps` shows the eviction clock:

```
NAME                      SIZE     PROCESSOR    CONTEXT    UNTIL
qwen3.8:27b-mtp-q4_K_M    17 GB    100% GPU     32768      4 minutes from now
```

Measured 2026-08-27: 21573 MiB resident, 1298 MiB after the timeout.
`OLLAMA_KEEP_ALIVE=-1` pins a model, `0` unloads after each request.

#### The LLM has priority on this card

Keep-alive is 2h, and any request re-arms the timer, so the model holds ~30 GB
for most of a working day. **That is the intended ordering, not a problem to
fix.** Long-running LLM sessions matter more here than ComfyUI, and losing the
prompt cache costs a full cold reprocess — minutes at 262144.

The consequence is that ComfyUI on `:8188` will often fail to load a checkpoint.
It surfaces as an out-of-memory or a load failure that reads as a ComfyUI fault,
so **check `ollama ps` first**. To hand the card over deliberately:

```bash
curl -s http://t1:11434/api/generate \
  -d '{"model":"qwen3.8:27b-mtp-q4_K_M-d3","keep_alive":0}'
```

Do not automate that from `comfyui-start.sh`. An automatic eviction would let a
background render silently destroy an in-flight session's cache; the manual step
is the point.

### Models

Models live at `/var/lib/ollama/{blobs,manifests}`. To migrate a store built
elsewhere:

```bash
sudo cp -a ~/srv/ollama/blobs/.     /var/lib/ollama/blobs/
sudo cp -a ~/srv/ollama/manifests/. /var/lib/ollama/manifests/
sudo chown -R ollama:ollama /var/lib/ollama
```

| Tag | Notes |
|---|---|
| `qwen3.8:27b-mtp-q4_K_M-d3` | **default since 2026-08-27.** Draft depth 3 |
| `qwen3.8:27b-mtp-q4_K_M` | upstream tag, draft depth 4 |

#### The `-d3` tag

Built locally, weights shared with the parent tag so it costs no disk:

```bash
printf '%s\n' 'FROM qwen3.8:27b-mtp-q4_K_M' 'PARAMETER draft_num_predict 3' > /tmp/Modelfile.d3
ollama create qwen3.8:27b-mtp-q4_K_M-d3 -f /tmp/Modelfile.d3
```

Depth 3 rather than the upstream 4. Measured 2026-08-27, `think: false`, greedy,
5 repeats, spread under 1% within a cell:

| task | context | depth 3 | depth 4 | depth 4 advantage |
|---|---|---|---|---|
| structured | empty | 182.85 | 193.59 | +5.9% |
| structured | 32k | 157.90 | 167.96 | +6.4% |
| prose | empty | 112.84 | 100.86 | **-10.6%** |
| prose | 32k | 106.50 | 97.37 | **-8.6%** |

Task type decides this, not context depth — the split is stable across both.

Those cells ran at the old 500 W cap. Re-measured at 575 W:

| task | context | depth 3 | depth 4 | depth 4 advantage |
|---|---|---|---|---|
| structured | empty | 192.98 | 209.43 | +8.5% |
| structured | 32k | 166.57 | 179.55 | +7.8% |
| prose | empty | 119.45 | 109.08 | **-8.7%** |
| prose | 32k | 112.65 | 104.52 | **-7.2%** |

**The power cap moved the answer.** Depth 4 gained more from the extra 75 W
(+6.9 to +8.2%) than depth 3 did (+5.5 to +5.9%), because a deeper draft does
more compute per verify step and so benefits more once the card stops being
power-limited. Break-even on time per token:

| context | at 500 W | at 575 W |
|---|---|---|
| empty | 77.6% structured | 66.2% |
| 32k | 69.9% structured | **61.4%** |

**Depth 3 still ships**, winning below 61.4% structured at production context,
but by a narrower margin than at 500 W. Two things keep that comfortable:

- these cells ran with `think: false`. Clients with thinking enabled emit
  reasoning prose before the answer whatever the task, which pushes the mix
  toward the case depth 3 wins. Zed is the one client with thinking off
- the effect is single-digit either way, so being wrong is cheap

If the workload ever becomes mostly non-thinking code generation, re-check it —
depth 4 is competitive now in a way it was not at 500 W. To revert, point
clients back at `qwen3.8:27b-mtp-q4_K_M`.

Verify the parameter reaches the engine, not just the manifest:

```bash
journalctl -u ollama | grep 'starting llama-server' | tail -1 | grep -o -- '--spec-draft-n-max [0-9]*'
```

#### Draft depth changes the output, and that is not a bug

Speculative decoding is supposed to be output-identical to plain greedy decoding.
Here it is not. Measured 2026-08-27 on 20 fixed greedy prompts, 600 tokens each:

| comparison | prompts diverging |
|---|---|
| depth 0 vs itself, depth 4 vs itself | **0/20** |
| depth 0 vs depth 4 | 18/20 |
| depth 0 vs depth 3 | 15/20 |
| depth 3 vs depth 4 | 16/20 |

Controls are clean and reproduced token-for-token across three runs, so the
engine is deterministic at fixed depth and depth is genuinely the cause.

**It is floating-point reduction order, not llama.cpp #25618.** Verifying N
drafted tokens in one pass changes the batch shape, which changes reduction
order, which flips logits that were already tied. Confirmed by replaying each
common prefix through an unspeculated decode on `llama-server` directly:

```bash
PORT=$(journalctl -u ollama | grep 'starting llama-server' | tail -1 | grep -o -- '--port [0-9]*' | awk '{print $2}')
curl -s "http://127.0.0.1:$PORT/completion" -d '{"prompt":[<token ids>],"n_predict":1,"n_probs":10,"temperature":0,"speculative.n_max":0,"cache_prompt":false}'
```

At all 49 divergence points both candidate tokens sat at oracle rank 0 or 1,
separated by a median 0.06 nats, and depth 4 matched the oracle argmax *more*
often than depth 3 (11/16 against 5/16). A broken accept path would rank the
speculated arm's token far down; it never did once. Corroborating: 1.83% of
positions are near-ties under 0.10 nats, so a 600-token generation passes ~11
coin-toss positions.

Consequence: depth is **not** quality-neutral by construction, so any quality
baseline must be run at the depth that will actually ship.

**ollama's `logprobs` cannot be used to investigate this.** It emits entries
only for tokens that pass through the normal sampler, so a speculated arm
returns 1-2 entries for 600 tokens while depth 0 returns all 600. Cross-arm
comparison in logprob space is silently misaligned. Use `llama-server` directly.

`qwen3.8:27b`, `:latest`, `:27b-q4_K_M` and `:27b-mtp-q4_K_M` share the same
**weights** digest (`sha256:f5f1dd8920d4…`), because for 3.8 the MTP head lives
inside the main GGUF rather than a separate repo.

**The `-mtp` tag is not cosmetic.** The params layer differs, and only the `-mtp`
tag carries `draft_num_predict`:

```
qwen3.8:27b-mtp-q4_K_M  ->  draft_num_predict 4
qwen3.8:27b-q8_0        ->  (absent)
```

`routes.go` zeroes `DraftNumPredict` unless a Modelfile or request names it, so
the other tags run with **speculation silently off**. That costs about 2.5x on
structured output, with no error and nothing in the logs to notice. Always pull
the `-mtp` tag, or set the parameter yourself.

If ComfyUI is holding VRAM and a model fails to load, unload its models:

```bash
curl -X POST http://localhost:8188/free -H 'Content-Type: application/json' -d '{"unload_models": true, "free_memory": true}'
```

That leaves the 498 MiB CUDA context behind — only stopping the process returns
it. `docker stop comfyui` does, and ComfyUI now stops itself after 30 idle
minutes anyway; see "On-demand start" under ComfyUI.

#### Other quants of Qwen3.8

| Tag | Size | Verdict |
|---|---|---|
| `27b-q4_K_M` | 17.74 GB | in use |
| `27b-nvfp4` | 18.17 GB | will not run |
| `27b-q8_0` | 29.98 GB | fits to ~8192 ctx only |
| `27b-mxfp8` | 31.66 GB | will not run; too large regardless |
| `27b-bf16` | 55.59 GB | too large |

**`nvfp4` and `mxfp8` are Apple builds despite the names.** Both fail with
`Error: this model requires MLX support, but the MLX runtime is not available`.
They use ollama's per-tensor layer format (~1200 layers against 4 for the GGUF
tags), which is MLX-only in 0.32.15. So the NVFP4 build does not run on NVIDIA,
even though the 5090 has native FP4 tensor cores.

`q8_0` leaves 2860 MiB after weights. f16 KV costs ~112 KiB/token, so 32768 ctx
needs 3584 MiB and does not fit. 8192 fits, before counting the ~1300 MiB the
desktop holds.

ollama is not limited to its own library. `ollama create` with `FROM ./model.gguf`
imports any GGUF, including unsloth's `UD-Q4_K_XL` (same size, higher fidelity
than `Q4_K_M`). Whether MTP survives the import is untested. MTP is worth
1.65–2.47x here, so check before switching.

### Benchmark: why ollama replaced llama.cpp (2026-08-27)

Decode throughput on the same model, 10 runs per cell, `--temp 0`, 400 tokens,
1 discarded warm-up. Each engine's own decode accounting, prompt eval excluded:
llama.cpp `timings.predicted_per_second`, ollama `eval_count / eval_duration`.

| Config | structured (JSON) | prose |
|---|---|---|
| llama.cpp, MTP off — baseline | 73.11 ± 0.31 | 72.58 ± 0.08 |
| llama.cpp + MTP, as deployed (262144, q4_0 KV) | 113.58 ± 0.96 | 92.96 ± 0.30 |
| llama.cpp + MTP, ctx-matched (32768, f16 KV) | 118.19 ± 1.08 | 92.99 ± 0.37 |
| **ollama + MTP** (32768, f16 KV) | **180.33 ± 1.67** | **119.43 ± 0.25** |

Against a context-matched llama.cpp, ollama is +53 % on structured output and
+28 % on prose. Against the config that was deployed, +59 % / +28 %. Re-measured
on the systemd service after the migration: **182.60 ± 1.15** and
**120.12 ± 0.68**.

Not a context artefact. The ctx-matched row exists to rule that out. Dropping
262144 → 32768 and q4_0 → f16 KV moved structured by 4 % and prose not at all.
Decode cost tracks tokens in the cache, not the allocation.

**This comparison was not controlled, and the conclusion below is retracted.**
ollama does not have its own inference engine for GGUF models. It spawns
`/usr/lib/ollama/llama-server` — the upstream binary, llama.cpp b10488. The two
runs therefore differed in draft depth (3 vs 4), model file (`UD-Q4_K_XL` vs
`Q4_K_M`), `--no-mmproj` vs a loaded 931 MB projector, and CUDA 12.8 container vs
CUDA 13 Arch build. A multi-variable difference was attributed to one cause.

What the acceptance data does support: MTP is worth 1.62x / 1.28x in the
llama.cpp run and 2.47x / 1.65x in the ollama run, and llama.cpp's acceptance was
0.74 structured / 0.54 prose.

That matches llama.cpp
[PR #27781](https://github.com/ggml-org/llama.cpp/pull/27781), open as of
2026-08-27. It reports `draft-mtp` misdetecting separate-KV MTP architectures,
qwen3_5 included, as sharing the target's KV. The draft head then runs from stale
state at pinned positions. Retest llama.cpp if it lands.

Limits of the test:

- Different quant builds. llama.cpp ran unsloth `UD-Q4_K_XL` (17.6 GB), ollama
  ships `Q4_K_M` (16.81 GB). ~4.5 % less weight bandwidth predicts a few percent,
  not the measured gap. But UD is the higher-fidelity quant, and the switch loses
  it
- ollama's own no-MTP baseline was not measured. `draft_num_predict: 0` does
  disable drafting, so this is measurable and simply was not done
- Throughput only. No quality comparison was made

### Quality baseline: 22/30 SWE-bench Verified (2026-08-27)

The first quality measurement ever taken on this box. Everything before it was
throughput only.

Run by the `crucible` harness against the served endpoint, 30 pinned SWE-bench
Verified instances, scored by the SWE-bench harness itself. Every resolved
instance shows a real FAIL_TO_PASS flip with zero PASS_TO_PASS regressions. Zero
infra failures, zero empty patches.

| repo | resolved |
|---|---|
| django | 10/11 |
| matplotlib | 3/4 |
| sphinx-doc | 3/5 |
| sympy | 2/4 |
| pydata | 2/2 |
| mwaskom | 1/1 |
| scikit-learn | 1/1 |
| astropy | 0/2 |

**Do not quote this as a percentage.** The subset is django-weighted — 11 of 30,
and django is where the model did best — and at n=30 the 95% interval is roughly
±16 points. It is a baseline to pair future runs against, not a statement about
the model on Verified. As a first answer to "can the served model do real
agentic work", it is clearly yes.

Arm config, for the paired re-run: `qwen3.8:27b-mtp-q4_K_M-d3`,
`draft_num_predict 3`, ollama 0.32.15, ctx 262144, q8_0 KV, spawns 18:55:58
port 34525 and 19:46:37 port 41061. Per-instance results retained, and the
retried-instance list is empty, so every pair in a second arm is clean.

Server side over the run: **842 requests, all HTTP 200**, zero aborts. Prompt
sizes peaked at 42,478 tokens — 16% of the window — so neither truncation nor
the 64k abort was ever in play.

### Tried and rejected: num_batch

Measured 2026-08-27. `num_batch` sets **both** `-b` and `-ub`, not just the
logical batch, so a real prefill gain was plausible. There is none.

The scheduler's own choice depends on context size — `-b 1024 -ub 1024` at ctx
32768, `-b 512 -ub 512` at 262144 — so the test that matters is at 262144, where
raising to 1024 is a genuine doubling. Run as default → 1024 → default so drift
is measured rather than assumed:

| cell | -b | -ub | prefill at 24k | VRAM |
|---|---|---|---|---|
| default-A | 512 | 512 | 2971 tok/s | 29838 MiB |
| nb1024 | 1024 | 1024 | 2962 tok/s | 30500 MiB |
| default-B | 512 | 512 | 2884 tok/s | 29838 MiB |

The two identical default cells differ by 2.9% and the treatment lands inside
that bracket. **Do not set it**: no gain, 662 MiB of VRAM, and setting it
explicitly disables ollama's OOM step-down, whose failure mode is a silent
partial offload rather than an error.

### Power cap 500 → 575 W: +6-8%, the largest single win

**575 W is both the card's maximum and its stock default.** The 500 W cap was a
deliberate detune from a
[thermal exercise](https://gist.github.com/tvararu/aef4e2da6580ff965bd122bcbd4b8ff0)
that measured only temperature and watts, never throughput. On LLM work it cost
6-8%. Restoring the default recovers it, and there is no headroom beyond.

Measured 2026-08-27, 8 rounds, cells **alternating** rather than bracketed —
changing the cap needs no model reload, so the two arms sit seconds apart under
near-identical thermal state, and the order flips every round:

| metric | 500 W | 575 W | gain | rounds 575 won |
|---|---|---|---|---|
| decode, structured | 179.87 | 190.54 | **+5.9%** | 8/8 |
| decode, prose | 111.82 | 119.08 | **+6.5%** | 8/8 |
| prefill, 24k cold | 2915 | 3153 | **+8.2%** | 8/8 |

Per-round deltas, which are drift-free by construction: structured +5.5% median
(sd 0.92), prose +6.3% (sd 0.80), prefill +8.0% (sd 0.42). Thermals stayed at
71-79 °C with clocks 2280-2655 MHz, so nothing throttled.

Prefill gains most, which fits: it is the most compute-bound of the three.

```bash
lact cli -g 1 power-limit get
lact cli -g 1 power-limit set 575
```

The `lact` CLI persists past LACT's own 5 s re-apply timer, so it is usable for
A/B work without editing `/etc/lact/config.yaml`. The config file still sets the
value at boot — change it there to make it stick.

**`nvidia-smi -pl` does not work here.** LACT re-applies `power_cap` every 5 s
and silently reverts it, so any benchmark after it measures the old value.

**Every throughput figure recorded above this section was measured at 500 W** —
the long-context curve, the depth-3 comparison and the crucible baseline
included. Ratios between arms hold, since both arms of each comparison shared a
cap, but absolute numbers are ~6-8% low against the current configuration.

### Benchmarking this box: thermal drift is ~3%

Sequential A/B cells drift about 3% across a run as the card heats, which is
larger than most effects worth chasing here. The num_batch test at ctx 32768
would have been written up as "explicit num_batch is 3.4% slower" — comparing
two cells that had *identical* spawn flags.

Any comparison with an expected effect under ~5% needs a bracketed or
interleaved order. Also worth pinning down before trusting a number:

- `prompt_eval_count` counts cached **plus** new tokens while
  `prompt_eval_duration` times only the new ones, so their ratio reads absurdly
  high on a cache hit. Above ~5000 tok/s means a cache hit; cold prefill peaks
  near 3000.
- A unique nonce at the **front** of the prompt forces full reprocessing.
- `think` changes the task profile. With thinking on, both structured and prose
  prompts emit prose-like reasoning first, which compresses the difference
  between them. Numbers taken with and without it are not comparable.
- Check `offloaded 66/66 layers` in the journal. A partial offload serves at a
  fraction of the rate with no error.

### What was given up

- **The dynamic quant**, `UD-Q4_K_XL` → `Q4_K_M`
- **Tuning knobs** — not actually given up. `draft_num_predict` maps to
  `--spec-draft-n-max`, `OLLAMA_KV_CACHE_TYPE` to `-ctk`/`-ctv`, and ollama passes
  the child `cmd.Env = os.Environ()`, so any `LLAMA_ARG_*` for a flag ollama does
  **not** set reaches llama-server. CLI beats env, so `-b`/`-ub`, `-ctk`/`-ctv`
  and `--spec-type` are the ones genuinely out of reach
- **HTTPS**, because Serve cannot proxy it. Tailscale is WireGuard, so the
  transport is encrypted and the peer authenticated regardless

### Cleanup after the migration

Reclaimed 2026-08-27:

| Path | Size | Notes |
|---|---|---|
| `~/srv/ollama/` | 17 GB | user-space store built for the benchmark; verified blob-for-blob against `/var/lib/ollama` first |
| `ghcr.io/ggml-org/llama.cpp:server-cuda` | 4.3 GB | `docker rmi`, unused once the profiles were gone |
| `~/srv/llama-server/` | 56 GB | llama.cpp GGUF cache. Re-downloadable |

The llama.cpp container ran as root, so the GGUFs it wrote into the
`deity`-owned bind mount were `root:root`. A plain `rm -rf` deleted ~22 GB, then
failed with `Permission denied` on the five large blobs and left the tree half
gone. It took `sudo rm -rf /home/deity/srv/llama-server` to finish.

Check for this anywhere a container writes into a bind mount as root:
`find <dir> -type f -printf '%u\n' | sort | uniq -c`.

A stale exited `llama-qwopus` container still held a mount reference to the
cache. Use `docker ps -a`. Stopped containers keep their mounts.

`/var/lib/ollama` holds `qwen3.8:27b-mtp-q4_K_M`, `qwen3.8:27b-mtp-q4_K_M-d3`
and `qwen3.8:27b-q8_0`, sharing 44 GB of blobs. Verified 2026-08-27.


## ComfyUI

ComfyUI via [mmartial/comfyui-nvidia-docker](https://github.com/mmartial/ComfyUI-Nvidia-Docker) on `ubuntu24_cuda13.1-latest`. The image clones upstream ComfyUI HEAD on first boot into a persistent venv at `~/srv/comfyui/`, so subsequent restarts skip the install step.

- **Port**: `127.0.0.1:8188`, held by `comfyui-proxy.socket` and fronted by `tailscale serve` on `:8188`; the container itself publishes `127.0.0.1:8189`
- **Run dir**: `~/srv/comfyui/` (venv, ComfyUI source, custom_nodes, uv cache — all persistent)
- **Models**: `~/models` bind-mounted to `/host_models`, symlinked into `/comfy/mnt/ComfyUI/models` by `user_script.bash`
- **Plugin bootstrap**: `~/srv/comfyui/user_script.bash` (mmartial auto-runs any file of that name)

### On-demand start (VRAM reclaim)

ComfyUI is not started by docker. `comfyui-proxy.socket` holds port 8188, and the
first connection starts the container; 30 minutes after the last one closes it is
stopped again.

The reason is a CUDA context. ComfyUI creates one at import and holds it for the
life of the process, with no model resident:

| State | VRAM | `torch_vram_total` |
| ----- | ---- | ------------------ |
| stopped | 0 MiB | — |
| running, nothing loaded | 498 MiB | 0 |

So the idle cost is the context, not weights, and `POST /free` cannot release it —
that only unloads models. Only stopping the process returns the memory, which
matters when llama-server routinely holds 29 GB of the 5090's 32 GB.

**If ComfyUI fails to load a checkpoint, suspect ollama before ComfyUI.** The
LLM has priority on this card and its keep-alive is 2h, so it will usually be
holding ~30 GB. Check `ollama ps`, then unload it deliberately — see "The LLM
has priority on this card" under Ollama.

Unlike Sunshine, this one really does resume on request. ComfyUI is plain HTTP
over TCP, so `systemd-socket-proxyd` applies, where Sunshine's UDP ruled it out.
A cold request measures **13.9s** to a served `200`, and the client never sees a
refusal: the socket unit accepts the connection immediately and holds it open
while the container starts.

Three units, in `sys/t1/`:

| Unit | Role |
| ---- | ---- |
| `comfyui-proxy.socket` | owns 8188, starts the proxy on first connection |
| `comfyui-proxy.service` | `systemd-socket-proxyd` to `127.0.0.1:8189`, `--exit-idle-time=30min` |
| `comfyui.service` | `docker start`/`stop` with a readiness wait and a queue drain |

The release path is `--exit-idle-time` plus `StopWhenUnneeded=yes`: the proxy
exits after 30 idle minutes, nothing then requires `comfyui.service`, systemd
stops it, and the socket re-arms for the next request.

**An open tab counts as busy.** The frontend holds a websocket for progress
updates, so the idle clock only starts once the last tab is closed. That is
deliberate — stopping under an open tab would drop the websocket, and the
frontend's automatic reconnect would restart the container immediately.

`comfyui-stop.sh` waits for `queue_remaining` to reach 0 before stopping, capped
at `DRAIN_TIMEOUT` (30 min). Without it, queueing a long render and closing the
tab would drop the connection count to zero and kill the job at the timeout. A
manual `systemctl stop comfyui` inherits the same wait, so it is not always
instant.

#### Port 8188 moved off the Docker path

The container now publishes `127.0.0.1:8189` and systemd owns 8188 on the host.
That changes which firewall chain the port goes through, and **needs a ufw rule
or LAN access breaks**:

- Before: a Docker-published port, filtered in `DOCKER-USER`, which RETURNs for
  RFC1918 — hence LAN worked and tailnet was dropped
- After: a host-bound port on the INPUT path, where the default policy is DROP
  and no rule for 8188 existed

Tailnet access starts working as a side effect, because `tailscaled` inserts its
own ACCEPT ahead of ufw (the same reason ollama on `100.73.138.96:11434` is
reachable with no rule). This also retires the `ufw route allow` workaround that
Docker-published ports need.

As of 2026-08-27 the socket binds `127.0.0.1:8188` and Serve owns the tailnet side,
so the INPUT path stopped mattering and the LAN rule went with it. To put it back
on the LAN, bind `ListenStream=192.168.8.192:8188` and restore the ufw allow.

#### Install

```bash
sudo install -m 644 ~/.dotfiles/sys/t1/comfyui.service \
                    ~/.dotfiles/sys/t1/comfyui-proxy.service \
                    ~/.dotfiles/sys/t1/comfyui-proxy.socket /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl reenable comfyui-proxy.socket
sudo systemctl start comfyui-proxy.socket
tailscale serve --bg --https=8188 127.0.0.1:8188
```

Copied, not symlinked — `/home` is not mounted when systemd loads units. Only the
socket is enabled; the two services are pulled in on demand and must not be.

`start` is a separate step because `reenable --now` is *try-restart*, which does
nothing to a unit that is not already running. `is-enabled` returning `enabled`
with no listener on 8188 is exactly that mistake.

Verify with the container stopped:

```bash
docker stop comfyui
time curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8188/system_stats   # 200, ~14s
systemctl status comfyui.service comfyui-proxy.service
```

To change the idle window, edit `--exit-idle-time` in `comfyui-proxy.service`.
`docker compose up -d` still starts the container directly, which is harmless —
the next idle period stops it.


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
| ~~ComfyUI-LTXVideo~~ (disabled) | Lightricks/ComfyUI-LTXVideo            |
| KJNodes                         | kijai/ComfyUI-KJNodes                  |
| Inpaint-CropAndStitch           | lquesada/ComfyUI-Inpaint-CropAndStitch |
| RMBG                            | 1038lab/ComfyUI-RMBG                   |

### Notes

- Bind-mounting models _inside_ the ComfyUI tree (e.g. `~/models:/comfy/mnt/ComfyUI/models`) breaks mmartial's init — Docker pre-creates the parent dir, mmartial then tries `git remote set-url` on a non-repo and loops on "subscript failed". Mount outside the tree and symlink in.
- `FORCE_CHOWN=true` is required — mmartial creates `/comfy/mnt/ComfyUI/` as root before chowning to `WANTED_UID`, and refuses to start if the perms don't match.
- The persistent venv means a `docker compose up -d --force-recreate comfyui` is fast (~30s); only image upgrades trigger a fresh torch+deps install.
- To upgrade ComfyUI itself: `git -C ~/srv/comfyui/ComfyUI pull && docker restart comfyui`.
- ComfyUI-LTXVideo is disabled. `pyramid_blending.py` imports `pad` from
  `kornia.geometry.transform.pyramid`, which kornia has removed, so the pack
  raised `ImportError` on every start and loaded none of its nodes. It is dropped
  from `user_script.bash` and the clone renamed to `ComfyUI-LTXVideo.disabled`;
  ComfyUI skips any `custom_nodes` directory with that suffix. Undo both to
  re-enable once upstream catches up with kornia. Nothing is lost meanwhile:
  LTX-Video is native to ComfyUI now (`comfy_extras/nodes_lt.py`,
  `nodes_lt_audio.py`, `nodes_lt_upsampler.py`), and `/object_info` still lists
  26 LTXV nodes with the pack disabled.
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

The broker is the reusable part. Point a copy of the publisher at t1 over the tailnet — bind mosquitto to the tailnet address as ollama already does, rather than exposing it to the LAN — and give sol its own broker user. Worth adding ZFS pool health, scrub status and per-drive temps there, and keeping the slow SMART interval since sol's disks actually spin.

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
