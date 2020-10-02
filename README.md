# Manjaro dotfiles

```bash
$ sudo pacman -U https://archive.archlinux.org/packages/s/stow/stow-2.2.2-5-any.pkg.tar.xz
$ cd ~
$ git clone https://github.com/tvararu/.dotfiles
$ cd .dotfiles
$ stow --adopt */  # Replaces all existing dotfiles with symlinks to this repo
$ git reset --hard # Updates local dotfiles to be the same as in the repo
$ stow --restow */ # Installs remaining dotfiles
$ ./pamac.sh
```
