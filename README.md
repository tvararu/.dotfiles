# Arch dotfiles and scripts

I use Arch Linux for tinkering, gaming, and productivity, in that order. This repo is my current hardware setup, dotfiles, and notes on how to get various things working.

## Hardware

```
CASE: Dan A4-SFX v4.1 7L
PSU: Corsair SF750
CPU: AMD Ryzen 5 3600XT 6C/12T 3.8GHz/4.5GHz
FANS: Asetek 645LT 92mm AIO + Noctua NF-A9x14 x2
MOTHERBOARD: Asus ROG STRIX B550-I GAMING mini-ITX
LAN: Intel I225-V 2.5Gb Ethernet
WLAN: Intel Wi-Fi 6 AX200
AUDIO: Realtek S1220A
RAM: Corsair Vengeance LPX 64GB DDR4 @ 3600MHz
GPU: Powercolor AMD Radeon RX 5700 XT Red Dragon
NVME0: Sabrent Rocket 1TB R/W 3400/3000
NVME1: Crucial P1 1TB R/W 2000/1700
SSD0: SanDisk Ultra II 1TB R/W 540/500

MONITOR: Philips S245E1S 1440p@75Hz FreeSync
KEYBOARD: Apple Magic Keyboard British
MOUSE: Logitech MX Master
WEBCAM: Logitech C920
```

Drivers: everything works out of the box on Linux kernel 5.8. `logiops-git` is necessary to change mouse settings.

## BIOS configuration

Boots fine in factory settings (secure boot is disabled), I then made these changes:

- Clocked RAM to 3600MHz
- Set water pump to 60% (inaudible) in all loads
- Set CPU and CHA fan to 20% (inaudible) when under 75C and 50% above (barely audible)

## Installing Arch

Get the [latest image](https://www.archlinux.org/download/) and `dd` it to a USB drive (macOS specific instructions):

```bash
$ diskutil list
$ diskutil unmountDisk /dev/diskX
$ sudo dd if=arch.iso of=/dev/rdiskX bs=1M
```

I then use [alis](https://github.com/picodotdev/alis) to configure and install the base system with the following options:

```bash
KEYS="us"

DEVICE="/dev/nvme0n1"
SWAP_SIZE="2048"

REFLECTOR="true"
REFLECTOR_COUNTRIES=("United Kingdom")
TIMEZONE="/usr/share/zoneinfo/Europe/London"
LOCALES=("en_GB.UTF-8 UTF-8")
LOCALE_CONF=("en_GB:en")
KEYMAP="KEYMAP=us"
KEYLAYOUT="us"
KEYMODEL="apple"
KEYVARIANT="mac"
KEYOPTIONS="caps:super"
HOSTNAME="arch"

BOOTLOADER="grub"

DESKTOP_ENVIRONMENT="i3-gaps"
DISPLAY_DRIVER="amdgpu"
VULKAN="true"

AUR="yay"
```

## Installing dotfiles and programs

```bash
$ sudo pacman -U https://archive.archlinux.org/packages/s/stow/stow-2.2.2-5-any.pkg.tar.xz # Older version until https://github.com/aspiers/stow/issues/65 is resolved
$ cd
$ git clone https://github.com/tvararu/.dotfiles.git
$ cd .dotfiles
$ ./packages.sh
$ ./atom.sh
$ chsh -s $(which fish)
$ stow --adopt */  # Replaces all existing dotfiles with symlinks to this repo
$ git reset --hard # Updates local dotfiles to be the same as in this repo
$ stow --restow */ # Installs remaining dotfiles
```

## System-specific configuration

### Audio

Arch selects the GPU as the default sound card. To switch to the motherboard sound card:

```bash
$ sudo vim /etc/modprobe.d/default.conf
options snd_hda_intel index=1
```

### Screen tearing

Firefox and other apps tear the screen when scrolling or otherwise changing large sections of the screen. Bumping the refresh rate from the default 60Hz to 75Hz and enabling FreeSync fixes it:

```bash
$ xrandr --rate 75
$ xrandr --output DisplayPort-0 --set TearFree on
```

To persist past restart:

```bash
$ sudo vim /etc/X11/xorg.conf.d/10-monitor.conf
Section "Device"
  Identifier "AMD"
  Driver     "amdgpu"
  Option     "TearFree" "true"
  Option     "VariableRefresh" "true"
EndSection

Section "Monitor"
  Identifier "DisplayPort-0"
  Option     "Primary" "true"
  Modeline   "2560x1440@75" 296.00 2560 2568 2600 2666 1440 1443 1448 1481 +hsync -vsync
  Option     "PreferredMode" "2560x1440@75"
EndSection
```

### Bluetooth

Auto power-on after boot:

```bash
$ sudo vim /etc/bluetooth/main.conf # Scroll to end
[Policy]
AutoEnable=true
$ systemctl enable --now bluetooth.service
```

Use `bluetoothctl` to detect, pair, trust, and connect to peripherals:

```bash
$ bluetoothctl
> power on
> paired-devices
Device 04:4B:ED:E4:56:A2 Theodor’s Keyboard
Device DA:3C:8B:06:59:6F MX Master
> scan on
> trust <mac>
> pair <mac>
> connect <mac>
```

When connecting to the Apple keyboard, you need to type in a pairing code. Without a second keyboard, you can use `onboard` as an on-screen keyboard.

### Mouse configuration

After installing `logiops-git`:

```bash
$ sudo vim /etc/logid.cfg
devices: ({
  name: "Wireless Mouse MX Master";
  hiresscroll: { hires: true; invert: true; target: false; };
});
$ systemctl enable --now logid.service
```

### `dmenu_recency`

The i3 config is set up to use `dmenu_recency`, which comes from [dmenu-manjaro](https://gitlab.manjaro.org/packages/community/dmenu-manjaro).

To install:

```bash
$ yay -R dmenu
$ git clone https://gitlab.manjaro.org/packages/community/dmenu-manjaro
$ cd dmenu-manjaro
$ makepkg -si
```

## License

Public domain.
