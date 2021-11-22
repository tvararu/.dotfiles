#!/bin/sh

echo "\n Hey there. Never mind me, just setting up your system.\n"

./defaults.sh

./homebrew.sh

stow -R fish git gpg ssh tmux vim

echo " All done! Enjoy.\n"
