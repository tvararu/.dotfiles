# Dotfiles and scripts

Dotfiles for macOS and Linux.

## Installing Arch

Run `archinstall` in the live CD. I choose the `i3` preset.

When prompted, I use this list of starter packages:

```
vim tmux htop firefox wpa_supplicant man-db networkmanager network-manager-applet dex xss-lock git
```

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

Install `i3status`:

```bash
$ yay -S autoconf libconfuse-dev libyajl-dev libasound2-dev libiw-dev \
  asciidoc libpulse-dev libnl-genl-3-dev meson
$ git clone https://github.com/tvararu/i3status.git
$ cd i3status
$ mkdir build
$ cd build
$ meson ..
$ ninja
$ sudo ninja install
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
$ mkdir -p .local/share .local/bin
$ touch .Xresources.local
$ cd .dotfiles
$ ./arch.sh
$ stow --adopt */  # Replaces all existing dotfiles with symlinks to this repo
$ git reset --hard # Updates local dotfiles to be the same as in this repo
$ stow --restow --ignore=".theme.*" */ # Installs remaining dotfiles
```

## macOS setup

```bash
$ ./macos.sh
```

## System-specific configuration

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

### Pausing media playback when unplugging headphones

```bash
$ sudo vim /etc/acpi/events/stop-music-when-headphones-unplug
event=jack/headphone HEADPHONE unplug
action=su - USER -c "env DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus playerctl pause"
$ sudo systemctl enable --now acpid
```

## License

Public domain.
