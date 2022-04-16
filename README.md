# Dotfiles and scripts

Dotfiles for macOS and Linux.

## Installing Arch

Run `archinstall` in the live CD. I choose the `i3` preset.

When prompted, I use this list of starter packages:

```
vim tmux htop firefox wpa_supplicant man-db networkmanager network-manager-applet dex xss-lock git
```

On my 2013 MacBook Air, I also get `broadcom-wl` for wireless drivers.

## Installing dotfiles and programs

Enable multilib packages:

```bash
$ sudo vim /etc/pacman.conf
[multilib]
Include = /etc/pacman.d/mirrorlist
$ sudo pacman -Syu
```

Install `yay`:

```bash
$ git clone https://aur.archlinux.org/yay-bin.git
$ cd yay-bin
$ makepkg -si
```

Install `st`:

```bash
$ git clone https://github.com/tvararu/st.git
$ cd st
$ sudo make install
$ yay -S libxft-bgra
```

Install `dmenu`:

```bash
$ git clone https://github.com/tvararu/dmenu.git
$ cd dmenu
$ make
$ sudo make install
```

Install `fish`:

```bash
$ yay -S fish
$ chsh -s $(which fish)
$ fish
$ rm -r .bash*
```

Then:

```bash
$ cd
$ git clone https://github.com/tvararu/.dotfiles.git
$ mkdir .ssh .vim .gnupg
$ touch .Xresources.local
$ cd .dotfiles
$ ./packages.sh
$ stow --adopt */  # Replaces all existing dotfiles with symlinks to this repo
$ git reset --hard # Updates local dotfiles to be the same as in this repo
$ stow --restow */ # Installs remaining dotfiles
```

## macOS setup

```bash
$ ./.macos/macos-install.sh
```

## System-specific configuration

### Wifi (MacBook Air)

After first-booting on my laptop:

```bash
$ sudo modprobe wl
$ sudo systemctl enable --now NetworkManager.service
$ nmtui
```

### Mounting an SD card

```bash
$ mkdir /mnt/SD
$ sudo vim /etc/fstab
UUID=<get using blkid>  /mnt/SD exfat defaults,uid=1000 0 2
```

### Syncthing

```bash
$ sudo systemctl enable --now syncthing@$USER.service
$ open http://127.0.0.1:8384
```

### Screen brightness

```bash
$ yay -S acpilight
$ sudo gpasswd -a $USER video
```

### Screen tearing

Firefox and other apps tear the screen when scrolling or otherwise changing large sections of the screen. Bumping the refresh rate from the default 60Hz and enabling FreeSync fixes it:

```bash
$ xrandr --rate 100
$ xrandr --output DisplayPort-0 --set TearFree on
```

To persist past restart:

```bash
$ cvt 3440 1440 100.00 # Generate modeline
$ xrandr --verbose -q  # Or extract it like this
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
  Modeline   "3440x1440_100.00"  543.50  3440 3488 3552 3600  1440 1443 1453 1510 -hsync +vsync
  Option     "PreferredMode" "3440x1440_100.00"
EndSection
```

### Bluetooth

Auto power-on after boot:

```bash
$ sudo vim /etc/bluetooth/main.conf # Scroll to end
[Policy]
AutoEnable=true
$ sudo systemctl enable --now bluetooth.service
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

### Keyboard

To change the overall keyboard layout to the one for an Apple ISO UK keyboard:

```bash
$ sudo localectl --no-convert set-x11-keymap gb apple mac
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

### `auto-cpufreq`

```bash
$ sudo systemctl enable --now auto-cpufreq
```

### Set timezone when connecting to a network

To automatically set the correct timezone when connecting to a new network:

```bash
$ sudo vim /etc/NetworkManager/dispatcher.d/09-timezone
#!/bin/sh
case "$2" in
    up)
        timedatectl set-timezone "$(curl --fail https://ipapi.co/timezone)"
    ;;
esac
```

### Don't lock sudo for 10 minutes if wrong password is provided

```bash
$ sudo vim /etc/security/faillock.conf
deny = 100
```

### Make screen blank/turn off after 1 hour

```bash
$ sudo vim /etc/X11/xorg.conf.d/10-monitor.conf
Section "ServerFlags"
  Option "StandbyTime" "60"
  Option "SuspendTime" "60"
  Option "OffTime" "60"
  Option "BlankTime" "60"
EndSection
```

### GUI scaling

```bash
$ echo "Xft.dpi:       192" >> .Xresources.local
$ echo "*.font: monospace:size=11" >> .Xresources.local
```

### Fingerprint reader

Restrict enrolling to the current user:

```bash
polkit.addRule(function (action, subject) {
  if (action.id == "net.reactivated.fprint.device.enroll") {
    return subject.user == "deity" ? polkit.Result.YES : polkit.Result.NO
  }
})
```

Enroll the finger:

```bash
$ fprintd-enroll deity
```

Modify `/etc/pam.d/{system-local-login,lightdm,sudo,i3lock}` by adding this
at the top:

```bash
auth		sufficient  	pam_unix.so try_first_pass likeauth nullok
auth		sufficient  	pam_fprintd.so
```

## License

Public domain.
