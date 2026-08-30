# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal dotfiles for macOS and Linux (Omarchy). Uses GNU Stow for symlinking.

## Structure

Each top-level directory is a stow package containing dotfiles in their target
path structure, except `sys/`, which holds per-machine system docs and service
definitions (not stowable; a catch-all `.stow-local-ignore` guards it).

Machines: `huginn` (MacBook Pro, macOS), `t1` (Omarchy desktop), `ymir`
(MacBook Air, Omarchy), `sol` (NAS).

## Systemd units

`sys/*/` holds unit files, but this repo lives under `/home`, which is not
mounted when systemd loads units:

- **Copy units into `/etc/systemd/system/`, never symlink them from here** — a
  symlinked unit reports `enabled` and `loaded` but silently never starts at boot
- Run `systemctl reenable` after copying: the `*.wants/` symlink is what systemd
  reads at boot, and fixing only the unit file leaves it pointing into `/home`
- `--now` means *try-restart* with `reenable` — a no-op on a stopped unit, so
  `systemctl start` explicitly afterwards
- Verify with `systemctl list-timers` showing a real NEXT; `is-enabled` is not
  evidence that a unit will run
- Scripts invoked by `ExecStart*` can stay in the repo — they are read at service
  start, long after `/home` is mounted

## Commands

```bash
# macOS (huginn) setup
./sys/huginn/setup.sh

# Stow a config (from repo root)
stow fish git nvim tmux
```

## Platform notes

- Packages on Omarchy: `omarchy pkg add <pkgs>` (repo) and `omarchy pkg aur add
  <pkgs>` (AUR) — thin wrappers over `pacman -S --needed` and `yay -S --needed`
  that verify the install; `omarchy pkg drop` to remove. Full upgrades are
  `omarchy update` only — it runs migrations and `--overwrite` for the omarchy
  package, which a raw `yay -Syu` / `pacman -Syu` skips. On sol (plain Arch)
  `yay` is fine
- `sys/t1/maintenance.md` contains Omarchy-specific system setup (keyboard, DDC
  brightness, boot)
- `sys/sol/maintenance.md` contains setup and maintenance log for `sol`, the
  home NAS (plain Arch, systemd-boot, ZFS)
- macOS-specific code uses `if test (uname) = Darwin` guards in fish
- After completing any Omarchy setup/config task, update `sys/t1/maintenance.md`
  with the steps
- After completing any sol setup/maintenance task, update
  `sys/sol/maintenance.md` with the steps
- `sudo` prompts for a password on t1 — surface privileged commands for the user
  to run rather than attempting them
- `maintenance.md` files accumulate stale sections that contradict newer ones —
  when hardware or paths change, grep for the old identifier and fix or mark
  every hit, and verify live state rather than trusting the notes

## Sol system administration

- Plain Arch on `linux-lts`, **not** Omarchy: systemd-boot (not Limine), plain
  `mkinitcpio -P`
- ZFS via `zfs-dkms` — after a kernel-bearing upgrade, defer module-loading ops
  (ufw, `zpool scrub`) until after reboot
- Data lives on ZFS pool `pool` at `/mnt/pool` (raidz1); never touch the pool
  disks
- sol has no git push access — author changes on the box, commit from elsewhere

## Omarchy system administration

- Quattro (4.x): Omarchy is the `omarchy` pacman package at `/usr/share/omarchy`
  (read-only, read it freely). Hyprland config is Lua in `~/.config/hypr/`; the
  bar, launcher, notifications, idle and lock are the Quickshell shell configured
  in `~/.config/omarchy/shell.json`. Use the `omarchy` skill for user config
- Package updates leave `.pacnew` files for Omarchy-owned `/etc` files; merge
  them, and re-insert `clevis` into `omarchy_hooks.conf` every time
- `limine-mkinitcpio` not `mkinitcpio -P` (Limine bootloader with UKI)
- `omarchy-snapshot restore` for btrfs rollbacks
- Hooks config: `/etc/mkinitcpio.conf.d/omarchy_hooks.conf` (drop-in overrides main config)
- Kernel cmdline: `/etc/default/limine` (not GRUB)
- Never add `ip=` kernel parameters — breaks Plymouth password prompt
- LUKS unlock goes through Clevis (hook: `clevis` before `encrypt`) — regenerating
  without it means a passphrase prompt at every boot (slot 0 still unlocks)
- For boot/initramfs changes: research Omarchy repo + community discussions first, never guess

## Commits

tpope style, no Conventional Commits prefix in this repo:

- Check `git log -n 5` first to match existing style
- Subject ≤50 chars, imperative mood, capitalized, no period
- Blank line, then 1-3 sentence body explaining "why"
- Always `git add` and `git commit` as separate commands
- Separate commits per logical change
- Prefix git with `mise exec --` — the `commit-msg` hook execs `hk`, which is
  mise-managed and missing from a bare PATH (same for `gh`)
- `hk` auto-wraps the body to 72 cols and fails the commit if the subject
  exceeds 50 chars, so don't hand-wrap
