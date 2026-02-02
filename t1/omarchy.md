# Omarchy setup log

This is a log of the various customisations I've done to my Omarchy setup.

## CLI Tools

```bash
yay -S fish git-delta lsd mosh tmux
```

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

## Boot: Disable Limine Timeout

```
# /boot/limine.conf
timeout: 0
graphics: yes
```

## Tailscale

```bash
yay -S tailscale
sudo systemctl enable --now tailscaled
sudo tailscale set --operator=$USER
tailscale up
```

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
timeout = 600   # 10min - screensaver
timeout = 1200  # 20min - lock screen
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
ExecStart=/home/deity/vms/openclaw.sh
ExecStop=/usr/bin/pkill -f openclaw.qcow2
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
