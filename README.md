# Dotfiles and scripts

Dotfiles for macOS and Linux.

## Hardware

Arch:

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

MONITOR: Philips 346P1CRH
KEYBOARD: Keychron K6 ISO GB
MOUSE: Logitech MX Master
WEBCAM: Logitech C920
```

## Installing Arch

Get the [latest image](https://www.archlinux.org/download/) and `dd` it to a USB drive (macOS specific instructions):

```bash
$ diskutil list
$ diskutil unmountDisk /dev/diskX
$ sudo dd if=arch.iso of=/dev/rdiskX bs=1m
```

I then use [alis](https://github.com/picodotdev/alis) to configure and install the base system with the following options:

```bash
KEYS="us"

DEVICE="/dev/nvme0n1"

REFLECTOR="true"
REFLECTOR_COUNTRIES=("United Kingdom")
TIMEZONE="/usr/share/zoneinfo/Europe/London"
LOCALES=("en_GB.UTF-8 UTF-8" "en_US.UTF-8 UTF-8")
LOCALE_CONF=("en_GB:en")
KEYMAP="KEYMAP=us"
KEYLAYOUT="gb"
KEYMODEL="apple"
KEYVARIANT="mac"
KEYOPTIONS=""
HOSTNAME="arch"

BOOTLOADER="grub"

DESKTOP_ENVIRONMENT="i3-gaps"
DISPLAY_DRIVER="amdgpu"
VULKAN="true"

AUR="yay"
```

## Installing dotfiles and programs

Enable multilib packages:

```bash
$ sudo vim /etc/pacman.conf
[multilib]
Include = /etc/pacman.d/mirrorlist
$ sudo pacman -Syu
```

Then:

```bash
$ cd
$ git clone https://github.com/tvararu/.dotfiles.git
$ cd .dotfiles
$ ./arch-install.sh
```

## macOS setup

```bash
$ ./macos-install.sh
```

## System-specific configuration

### Screen tearing

Firefox and other apps tear the screen when scrolling or otherwise changing large sections of the screen. Bumping the refresh rate from the default 60Hz and enabling FreeSync fixes it:

```bash
$ xrandr --rate 100
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

Section "Monitor"
  Identifier "HDMI-A-0"
  Option     "PreferredMode" "1920x1080"
  Option     "RightOf" "DisplayPort-0"
  Option     "Rotate" "right"
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
Device DA:3C:8B:06:59:70 MX Master
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

### `grub`

Add the following options to the grub config:

```bash
$ sudo vim /etc/default/grub
GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3"
GRUB_ENABLE_CRYPTODISK=y
$ sudo grub-mkconfig -o /boot/grub/grub.cfg
```

### `xkeysnail`

To use macOS style keybindings globally in apps, you need to allow `xkeysnail` to run as root:

```bash
$ sudo groupadd -f uinput
$ sudo gpasswd -a $USER input
$ sudo vim /etc/udev/rules.d/70-xkeysnail.rules
KERNEL=="uinput", GROUP="uinput", MODE="0660", OPTIONS+="static_node=uinput"
KERNEL=="event[0-9]*", GROUP="uinput", MODE="0660"
```

To change the overall keyboard layout to the one for an Apple ISO UK keyboard:

```bash
$ sudo localectl --no-convert set-x11-keymap gb apple mac
```

### `betterlockscreen`

To lock the screen when suspended:

```bash
$ systemctl enable betterlockscreen@$USER
```

### `onedrive`

Log into OneDrive and start it on system boot:

```bash
$ onedrive
$ systemctl enable --now onedrive@$USER.service
```

### `transmission-daemon`

Use the system user instead of `transmission`:

```bash
$ sudo systemctl edit transmission.service
[Service]
User=deity
```

To start now and on startup:

```bash
$ sudo systemctl enable --now transmission.service
```

## License

Public domain.
