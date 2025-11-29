# Omarchy setup log

This is a log of the various customisations I've done to my Omarchy setup.

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

## Git: SSH Commit Signing

```bash
cat > ~/.gitconfig.local << 'EOF'
[user]
  signingkey = ~/.ssh/id_ed25519.pub
[commit]
  gpgsign = true
[gpg]
  format = ssh
EOF

echo "$(git config user.email) $(cat ~/.ssh/id_ed25519.pub)" > ~/.gitallowedsigners
git config --global gpg.ssh.allowedSignersFile ~/.gitallowedsigners
```

Add the SSH key to GitHub as a **signing key** (not just auth):

```bash
cat ~/.ssh/id_ed25519.pub | wl-copy
```
