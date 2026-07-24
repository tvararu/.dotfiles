# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal dotfiles for macOS and Linux (Omarchy). Uses GNU Stow for symlinking.

## Structure

Each top-level directory is a stow package containing dotfiles in their target
path structure, except `sys/`, which holds per-machine system docs and service
definitions (not stowable; a catch-all `.stow-local-ignore` guards it).

Machines: `huginn` (this MacBook), `t1` (Omarchy desktop), `sol` (NAS).

## Commands

```bash
# macOS (huginn) setup
./sys/huginn/setup.sh

# Stow a config (from repo root)
stow fish git nvim tmux
```

## Platform notes

- Always use `yay` instead of `pacman` on Arch/Omarchy
- `sys/t1/maintenance.md` contains Omarchy-specific system setup (keyboard, DDC
  brightness, boot)
- macOS-specific code uses `if test (uname) = Darwin` guards in fish
- After completing any Omarchy setup/config task, update `sys/t1/maintenance.md`
  with the steps

## Omarchy system administration

- Omarchy source is at `~/code/omarchy` — check it before any system-level changes
- `limine-mkinitcpio` not `mkinitcpio -P` (Limine bootloader with UKI)
- `omarchy-snapshot restore` for btrfs rollbacks
- Hooks config: `/etc/mkinitcpio.conf.d/omarchy_hooks.conf` (drop-in overrides main config)
- Kernel cmdline: `/etc/default/limine` (not GRUB)
- Never add `ip=` kernel parameters — breaks Plymouth password prompt
- LUKS auto-unlock uses Clevis + TPM2 (hook: `clevis` before `encrypt`)
- For boot/initramfs changes: research Omarchy repo + community discussions first, never guess

## Commits

tpope style, no Conventional Commits prefix in this repo:

- Check `git log -n 5` first to match existing style
- Subject ≤50 chars, imperative mood, capitalized, no period
- Blank line, then 1-3 sentence body explaining "why"
- Always `git add` and `git commit` as separate commands
- Separate commits per logical change
