# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal dotfiles for macOS and Linux (Omarchy). Uses GNU Stow for symlinking.

## Structure

Each directory contains dotfiles in their target path structure.

## Commands

```bash
# macOS setup
./macos.sh

# Stow a config (from repo root)
stow fish git nvim tmux
```

## Platform notes

- Always use `yay` instead of `pacman` on Arch/Omarchy
- `t1/omarchy.md` contains Omarchy-specific system setup (keyboard, DDC brightness, boot)
- macOS-specific code uses `if test (uname) = Darwin` guards in fish
- After completing any Omarchy setup/config task, update `t1/omarchy.md` with the steps

## Omarchy system administration

- Omarchy source is at `~/code/omarchy` — check it before any system-level changes
- `limine-mkinitcpio` not `mkinitcpio -P` (Limine bootloader with UKI)
- `omarchy-snapshot restore` for btrfs rollbacks
- Hooks config: `/etc/mkinitcpio.conf.d/omarchy_hooks.conf` (drop-in overrides main config)
- Kernel cmdline: `/etc/default/limine` (not GRUB)
- Never add `ip=` kernel parameters — breaks Plymouth password prompt
- LUKS auto-unlock uses Clevis + TPM2 (hook: `clevis` before `encrypt`)
- For boot/initramfs changes: research Omarchy repo + community discussions first, never guess
