#!/bin/sh

echo "Setting up Arch."

./arch-packages.sh

chsh -s $(which fish)

stow --adopt */  # Replaces all existing dotfiles with symlinks to this repo
git reset --hard # Updates local dotfiles to be the same as in this repo
stow --restow */ # Installs remaining dotfiles

echo "All done!"
