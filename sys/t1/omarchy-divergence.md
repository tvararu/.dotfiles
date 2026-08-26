# Omarchy divergence audit — t1

Audited **2026-08-26** against **Omarchy 3.8.5** (`f4378f0d`), compared with a
throwaway vanilla install of the same commit in an Incus VM.

| | t1 | vanilla 3.8.5 |
|---|---|---|
| Packages (total / explicit) | 1153 / 188 | 950 / 170 |
| Orphans | 27 | **0** |
| Foreign (AUR) | 25 | **0** |
| Base packages missing | **36 of 149** | 0 |
| `~/.config` files differing from default | **23** (19 meaningful) | — |
| Distinct install steps run | 49 (2025-11-29, 0 failures) | 88 (1 expected failure) |

## Verdict

**The box has drifted far less than it felt like, and almost none of the drift is
accidental.** Of the 36 missing base packages, 32 were removed deliberately — 30 of
them within twenty minutes of first boot — and 11 of those are exactly what Omarchy's
own `omarchy-remove-preinstalls` removes today. The de-omakase was ahead of upstream,
not divergent from it.

The genuine problems are small, specific, and all of one kind: **an application was
removed but the thing that calls it was not.** Five keybindings, two screen-recording
entry points, and three menu entries invoke binaries that no longer exist. Nothing
warns; they just do nothing.

Going back to vanilla is **not worth it and not necessary.** The config surface is
23 files, and four of those are noise: two differ only by whitespace or key order,
one is written by Chromium itself, and one is a theme for an app that is gone. The
remaining 19 are mostly deliberate and well-commented. The 27 orphans and 25 AUR
packages are entirely ours — vanilla has zero of each — being the gaming stack and
this morning's AUR rebuilds, not Omarchy residue. Fixing the dead call sites is
roughly a dozen lines of work, and leaves the box more correct than a reinstall
would.

**A theory the VM disproved.** Omarchy applies install-time config through
`install/config/*.sh`, which run only at install. 43 such steps have been added since
t1 was built, so it looked like t1 must be missing all of them. It is not: migrations
mirror nearly all of them, and direct testing found only one artifact actually absent
(`~/.config/gtk-3.0/bookmarks`). The delivery mechanism works better than its shape
suggests. This is the finding that most justified building the VM.

## What is actually broken

Each verified by resolving the call site and confirming the binary is absent.

### Dead keybindings — 5

`~/.config/hypr/bindings.conf` still binds apps removed on install day:

| Binding | Launches | Status |
|---|---|---|
| `SUPER SHIFT M` | `spotify` | missing |
| `SUPER SHIFT G` | `signal-desktop` | missing |
| `SUPER SHIFT O` | `obsidian` | missing |
| `SUPER SHIFT W` | `typora` | missing |
| `SUPER SHIFT /` | `1password` | missing |

Upstream solved this after the fact: `omarchy-remove-preinstalls` swaps
`bindings.conf` for `default/hypr/plain-bindings.conf`. **Do not run that script** —
it would also remove all web apps and TUI wrappers and drop the web-app bindings
that are wanted. Delete the five lines instead.

### Screen recording — dead via two entry points

`ALT PRINT` and waybar's `custom/screenrecording-indicator` both call
`omarchy-capture-screenrecording`, which execs `gpu-screen-recorder` unconditionally
— no guard, no install prompt. The package was removed 2025-11-29.

Screenshots are unaffected: `grim`, `slurp`, `satty`, `wl-copy` and `hyprpicker` are
all present, so `PRINT` and OCR extraction work.

### Share menu — dead, plus two inert extensions

`omarchy-menu` → Share → Clipboard / File / Folder all call `localsend`, removed on
install day. Separately, `~/.local/share/nautilus-python/extensions/` holds
`localsend.py` and `transcode.py`, but `nautilus-python` is not installed, so
Nautilus never loads them — the files sit on disk doing nothing.

### `~/.local/bin` is not on the graphical session PATH

`~/.config/uwsm/env` reads:

```
export PATH=$OMARCHY_PATH/bin:$PATH
```

Upstream changed this to append `:$HOME/.local/bin` on **2026-03-12** (`dc238002`).
That commit shipped **no migration**, and the only migration that ever refreshes
`uwsm/env` is dated 2025-09-16 — six months earlier — so no existing install has ever
received it.

15 binaries live in `~/.local/bin`, including `claude`, `yt-dlp`, `codex` and `pi`.
The login shell has the directory (fish sets it), so terminals are fine; anything
launched by uwsm as a graphical app is not. This is why Sunshine's `apps.json` needs
its `"PATH": "$(PATH):$(HOME)/.local/bin"` workaround.

### Display pinned well below what the panel supports

`~/.config/hypr/monitors.conf` sets `monitor = ,1920x1200@60,auto,1.5` under a comment
reading *"Permissive fallback for the cable-swap to NVIDIA HDMI … Tune up once we see
what's plugged in."* That tune-up never happened. The dummy plug advertises
**2880x1800@100** and **2560x1600@120**; the desktop runs at 1920x1200@59.9.

Scale 1.5 is deliberate and reads well when streamed — that is not in question. Only
the **mode** is pinned low, by a line that describes itself as temporary.

### `tmux.conf` lost the Omarchy defaults

`~/.config/tmux/tmux.conf` is 2 lines; the Omarchy default is 104. The dotfiles
repo's `tmux/.config/tmux/tmux.conf` holds exactly those 2 lines, and the file on t1
is a **real file, not a stow symlink** — so the content was copied over the Omarchy
default at some point. Lost: `C-Space` prefix, vi copy mode, pane/window bindings,
and its theme colour block. (That block is static colours, not wired to
`~/.config/omarchy/current/theme` — 83 directives in total.)

Nothing else under `~/.config` is stow-managed, so this is the only place the
dotfiles repo and Omarchy collide.

### Two migrations failed and were skipped permanently

`omarchy-migrate` records a failed migration under
`~/.local/state/omarchy/migrations/skipped/` and never retries it. Two are there:

| Migration | Purpose | Skipped |
|---|---|---|
| `1767306902` | Migrate to new theme setup | 2026-01-18 |
| `1769183359` | Add `nautilus-python` package | 2026-03-03 |

The second explains the inert Nautilus extensions above. The first turned out to be
harmless: vanilla's `~/.config/omarchy/current/theme` is a real directory, exactly
like t1's, and both `themes/` dirs are empty — the theme layout matches.

Skipped migrations are invisible: nothing surfaces them, and no command lists them.

### Smaller stale forks

| File | Missing from upstream |
|---|---|
| `kitty/kitty.conf` | `cursor_blink_interval 0`, `shell_integration no-cursor` |
| `swayosd/config.toml` | still the old relative `style = "./style.css"` (upstream uses an absolute path) |
| `waybar/config.jsonc` | bluetooth `format-off` icon, `on-scroll-*` no-op overrides |
| `fastfetch/config.jsonc` | upstream simplified the uptime expression |
| `~/.config/gtk-3.0/bookmarks` | absent — the only `install/config` artifact genuinely missed |

## Deliberate and correct — no action

These differ from vanilla on purpose and should stay:

- **NVIDIA env** in `hyprland.conf` (`NVD_BACKEND`, `LIBVA_DRIVER_NAME`,
  `__GLX_VENDOR_LIBRARY_NAME`) and `cursor { no_hardware_cursors = 0 }` in
  `looknfeel.conf` — both well-commented, both load-bearing for the streaming setup.
- **`ghostty` as terminal** over `alacritty` (`xdg-terminals.list`) — now the
  sanctioned choice via `omarchy-install-terminal`.
- **`mise-git` over `mise`**, `gh` via mise rather than `github-cli`.
- **`hyprsunset` profile** enabled at 19:00; **`kb_layout = gb` / `kb_variant = mac`**;
  faster key repeat; `git/config` identity.
- **27 orphans / 25 AUR packages** — vanilla has zero of each, so all are ours: the
  lib32 gaming chain (2025-12-01) and this morning's AUR build dependencies. The
  `lib32-mpg123` → `lib32-jack2` chain stays blocked upstream; leave it.
- **Printing removed** (`cups*`) — vanilla enables `cups.service`/`cups-browsed.service`;
  t1 does not. Correct if printing is not wanted.

## Unused customisation mechanisms

Omarchy has since added the sanctioned extension points, and t1 has none of them:

- `~/.config/omarchy/hooks/{post-update,theme-set,font-set,battery-low,post-boot}.d/`
  — t1 has only the old flat `*.sample` files. **Not broken**: `omarchy-hook` reads
  both layouts and skips `*.sample`, so nothing currently runs either way.
  `omarchy-hook-install <type> <file>` creates the `.d` dir on demand.
- `~/.config/omarchy/extensions/menu.sh` — override parts of `omarchy-menu`.
- `~/.config/omarchy/themed/*.tpl` — per-theme templated config.

All three are purely additive to create. This is where future customisation belongs,
rather than editing Omarchy's own files.

## Package divergence, classified

36 base packages missing. **Never restore column A** — Omarchy removes those itself.

| Bucket | Count | Packages |
|---|---|---|
| **A · Sanctioned** — `omarchy-remove-preinstalls` drops these too | 11 | `1password-beta` `1password-cli` `claude-code` `kdenlive` `libreoffice-fresh` `obsidian` `obs-studio` `signal-desktop` `spotify` `typora` `xournalpp` |
| **B · Deliberately replaced** | 3 | `mise`→`mise-git`, `github-cli`→mise `gh`, `alacritty`→`ghostty` |
| **C · Removed, nothing calls them** | 18 | `alsa-utils` `asdcontrol` `cups` `cups-browsed` `cups-filters` `cups-pdf` `evince` `ffmpegthumbnailer` `gvfs-mtp` `gvfs-nfs` `gvfs-smb` `luarocks` `python-poetry-core` `python-terminaltexteffects` `ruby` `sushi` `system-config-printer` `tobi-try` |
| **D · Removed, something still calls them** | 4 | `gpu-screen-recorder` `localsend` `nautilus-python` `python-gobject` |

Buckets are disjoint and sum to 36. Cutting across them, **4 packages never arrived
at all** — `alacritty`, `alsa-utils`, `claude-code` and `nautilus-python` were added
to the manifest after t1 was built and appear nowhere in `pacman.log`. The other 32
were installed by Omarchy and then removed — 30 on install day, and just two since
(`github-cli` and `mise`, both replaced by mise-managed equivalents in March 2026).

`asdcontrol` sits in C rather than D on a technicality: `omarchy-brightness-display-apple`
does call it, but only for Apple Studio/XDR displays, which t1 does not have.

Bucket C is safe to leave. Restoring the Nautilus group (`gvfs-*`, `sushi`,
`ffmpegthumbnailer`, `nautilus-python`, `python-gobject`) buys network/phone browsing,
space-bar preview and video thumbnails — worth it only if those are wanted.

## Action checklist

Reviewed and decided 2026-08-26. **All twelve are resolved.** Base packages missing
fell from 36 to 26; the remaining 26 are all deliberate (bucket A, B and the parts of
C that were kept).

One thing has not taken effect yet: the `uwsm/env` PATH change applies at **next
login**, and Sunshine's workaround is already gone, so `~/.local/bin` is absent from
the graphical session until you log out and back in. Nothing currently depends on it
— the Sunshine Desktop entry launches no command — but a re-login closes the gap.

| # | Action | Decision | Status |
|---|---|---|---|
| 1 | Five dead keybindings | delete all five | **done** |
| 2 | `uwsm/env` PATH + drop Sunshine's workaround | apply both | **done** — `uwsm/env` now byte-identical to upstream |
| 3 | Screen recording | install `gpu-screen-recorder` | **done** — 6.0.1, both entry points live |
| 4 | Share menu | reinstall `localsend` | **done** — 1.18.2, all three entries live |
| 5 | Display mode | leave at 1920x1200@60 | no change, by choice |
| 6 | `tmux.conf` | Omarchy default + the 2 personal lines | **done** — 108 lines |
| 7 | Extension points | create all three, matching vanilla | **done** — structure now identical to the VM |
| 8 | Stale forks | refresh kitty, swayosd, waybar | **done** — backups kept as `*.bak.<epoch>` |
| 9 | `gtk-3.0/bookmarks` | create | **done** |
| 10 | Nautilus/desktop group | restore all seven | **done** — both Nautilus extensions import cleanly |
| 11 | Skipped migrations | clear both markers | **done** — both re-run on next update |
| 12 | Printing | leave removed | no change, by choice |

Two things surfaced while applying these:

- **The waybar refresh re-introduced a dead call site.** Upstream's `config.jsonc`
  hardcodes `"on-click-right": "alacritty"`, which this box does not have. Changed to
  `xdg-terminal-exec`, matching the convention the same file already uses elsewhere.
  Worth remembering: refreshing a config toward vanilla can *create* breakage on a
  box whose package set is not vanilla.
- **Restarting waybar from a non-graphical shell kills it.** `omarchy-restart-waybar`
  resolves to `systemd-run --user --scope`, and a scope inherits the caller's
  environment rather than the systemd user manager's — so without `WAYLAND_DISPLAY`
  it dies on launch while systemd logs "Started waybar". This is almost certainly the
  same mechanism behind the "invisible top bar" seen previously.

**Never run** `omarchy-reinstall`, `omarchy-reinstall-pkgs` or
`omarchy-reinstall-configs`. The first two run `pacman -Suu` (downgrades) and reset
mirrors to the stable channel; the third does `cp -R config/* ~/.config/` with no
backup. Any of them would endanger the nvidia-dkms / Sunshine / gaming stack.
`omarchy-refresh-config <path>` is the safe per-file equivalent.

## Method and blind spots

Sources: `/var/log/pacman.log` (unrotated, complete to 2025-11-29 — **protect it**,
it is the only full record and t1 has no `logrotate`), t1's original
`/var/log/omarchy-install.log`, the Omarchy checkout (clean, zero local
modifications), and a vanilla VM at the same commit.

The VM was an Arch cloud image with Omarchy installed via `install.sh` pinned to
`f4378f0d`, verified by `rev-parse`. Two deviations, both non-configuring: the
btrfs-root guard was bypassed (equivalent to answering "Proceed anyway"), and the
failure handler's interactive menu was made non-interactive. 92 of 93 steps
completed; only `login/limine-snapper.sh` failed, on "Limine config not found".

**Not covered by the VM:** bootloader, initramfs/UKI, Plymouth, snapper, and all
hardware-conditional config — the VM has no NVIDIA, so that branch never ran. The
Arch cloud image also contributes packages Omarchy did not (`cloud-init`, `grub`,
`dhcpcd`, `netctl`, `vim`, `logrotate`), so the raw 198-package difference overstates
Omarchy's contribution and was not used as a finding.

`/etc/sudoers.d` is `0750 root:root` and unreadable without root, which produced a
false "missing on t1" result for several files during the run. `deny = 10` in
`/etc/security/faillock.conf` confirms those steps did run. Any future `/etc`
comparison needs root on both sides to be trustworthy.
