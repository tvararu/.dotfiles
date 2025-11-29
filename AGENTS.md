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
- `omarchy.md` contains Omarchy-specific system setup (keyboard, DDC brightness, boot)
- macOS-specific code uses `if test (uname) = Darwin` guards in fish
- After completing any Omarchy setup/config task, update `omarchy.md` with the steps
