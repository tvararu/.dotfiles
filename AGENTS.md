# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal dotfiles for macOS and Linux (Omarchy). Uses GNU Stow for symlinking.

## Structure

Each top-level directory is a stow package containing dotfiles in their target
path structure, except `sys/`, which holds per-machine system docs and service
definitions (not stowable; a catch-all `.stow-local-ignore` guards it).

Machines: `huginn` (this MacBook), `t1` (Omarchy desktop), `sol` (NAS), `mimir`
(Ubuntu VM on huginn, via OrbStack), `luna` (Ubuntu VM on sol, via Incus).

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
- `sys/sol/maintenance.md` contains setup and maintenance log for `sol`, the
  home NAS (plain Arch, systemd-boot, ZFS)
- `sys/mimir/maintenance.md` contains setup and maintenance log for `mimir`, the
  Ubuntu VM Claude runs in; `sys/mimir/cloud-init.yml` provisions it
- `sys/luna/maintenance.md` contains setup and maintenance log for `luna`, the
  Incus VM on sol; `sys/luna/cloud-init.yml` provisions it and
  `sys/sol/incus-preseed.yml` configures the Incus host
- macOS-specific code uses `if test (uname) = Darwin` guards in fish
- After completing any Omarchy setup/config task, update `sys/t1/maintenance.md`
  with the steps
- After completing any sol setup/maintenance task, update
  `sys/sol/maintenance.md` with the steps
- After completing any mimir setup task, update `sys/mimir/maintenance.md` with
  the steps, and fold VM-creation-time changes into `sys/mimir/cloud-init.yml`
- After completing any luna setup task, update `sys/luna/maintenance.md` with the
  steps, and fold VM-creation-time changes into `sys/luna/cloud-init.yml`

## Sol system administration

- Plain Arch on `linux-lts`, **not** Omarchy: systemd-boot (not Limine), plain
  `mkinitcpio -P`
- ZFS via `zfs-dkms` — after a kernel-bearing upgrade, defer module-loading ops
  (ufw, `zpool scrub`) until after reboot
- Data lives on ZFS pool `pool` at `/mnt/pool` (raidz1); never touch the pool
  disks
- sol has no git push access — author changes on the box, commit from elsewhere

## Omarchy system administration

- Omarchy source is at `~/code/omarchy` — check it before any system-level changes
- `limine-mkinitcpio` not `mkinitcpio -P` (Limine bootloader with UKI)
- `omarchy-snapshot restore` for btrfs rollbacks
- Hooks config: `/etc/mkinitcpio.conf.d/omarchy_hooks.conf` (drop-in overrides main config)
- Kernel cmdline: `/etc/default/limine` (not GRUB)
- Never add `ip=` kernel parameters — breaks Plymouth password prompt
- LUKS unlock goes through Clevis (hook: `clevis` before `encrypt`) — changing
  hook order or regenerating without it will lock the machine out at boot
- For boot/initramfs changes: research Omarchy repo + community discussions first, never guess

## Commits

tpope style, no Conventional Commits prefix in this repo:

- Check `git log -n 5` first to match existing style
- Subject ≤50 chars, imperative mood, capitalized, no period
- Blank line, then 1-3 sentence body explaining "why"
- Always `git add` and `git commit` as separate commands
- Separate commits per logical change
