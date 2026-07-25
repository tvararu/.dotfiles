# mimir

Ubuntu 26.04 aarch64 VM running under OrbStack on `huginn`. It exists so Claude
can run with `--dangerously-skip-permissions` without prompting, and so dev
tooling stays off the Mac.

## Create

```bash
cd ~/.dotfiles
orb create -c sys/mimir/cloud-init.yml ubuntu mimir
```

`cloud-init.yml` installs tmux, curl, git, build-essential and unzip via apt,
then `claude` and `mise`, then writes `~/.config/mise/config.toml`,
`~/.gitconfig` and `~/.gitignore.global` and runs `mise install`.

apt is only used for what mise cannot provide: `git`, `build-essential` (rust
needs a linker) and `unzip` (bun ships as a zip). Everything else comes from
mise, including `npm:`/`cargo:`/`gem:` backed tools.

## Post-create steps

Populate the allowed signers file from the forwarded SSH agent. This can't
happen during cloud-init because the agent isn't reachable at boot:

```bash
echo "theo@vararu.org $(ssh-add -L)" > ~/.gitallowedsigners
```

Only needed for local signature verification, not for signing itself.

## Commit signing

OrbStack forwards the host SSH agent to
`$SSH_AUTH_SOCK=/opt/orbstack-guest/run/host-ssh-agent.sock`, backed by
Secretive's Secure Enclave key (`c1bf1329…`, the same one huginn signs with). No
key material lives in the VM. Signing works without a Touch ID prompt, and
`ssh -T git@github.com` authenticates as `tvararu` over the same agent.

Secretive is unreliable when AFK or with the screen off; if signing fails,
commit with `--no-gpg-sign` rather than debugging it.

`gpg.ssh.defaultKeyCommand` pulls the key from the agent instead of the
macOS-only `signingkey` path, which is the only difference that matters versus
huginn's gitconfig. Two intentional deviations besides: no `delta` pager (ANSI
decoration is noise in an agent's context window) and `editor = vim`.

Note: huginn's own `~/.gitallowedsigners` still lists the rotated-out
`21d14444…` key, so local verification of recent commits fails there. Unrelated
to mimir, but worth fixing on huginn at some point.

## Filesystem boundary

The Mac is mounted read-write at `/Users`, `/Applications`, `/Library`,
`/Volumes`, `/private` and `/mnt/mac`, and `/opt/orbstack-guest/bin` puts `mac`,
`open`, `osascript` and `screencapture` on PATH. This is not a sandbox. Work
lives in `~/code`; repos from `/Users/deity/Code` get symlinked in as needed.

## Docker

Not installed in the VM — huginn already runs Docker via OrbStack, and its
machines and volumes are visible at `/mnt/machines`.

## Claude config

`~/.claude/CLAUDE.md` inside the VM documents all of the above for Claude
itself. It's deliberately untracked and dies with the VM; this file is the
durable record.
