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

## Symlinked repos

Repos live at `/Users/deity/Code/<name>` and are symlinked in with
`ln -s /Users/deity/Code/<name> ~/code/<name>`. One gotcha: mise walks up from
the working directory, finds the Mac's `/Users/deity/.config/mise/config.toml`,
and refuses to run because it is untrusted — and it declares `python` and `ruby`
which the VM deliberately lacks. Ignore it once:

```bash
mise trust --ignore /Users/deity/.config/mise/config.toml
```

Then `mise trust --yes && mise install` in the repo as usual.

## Post-create steps

Populate the allowed signers file from the forwarded SSH agent. This can't
happen during cloud-init because the agent isn't reachable at boot:

```bash
echo "theo@vararu.org $(ssh-add -L)" > ~/.gitallowedsigners
```

Only needed for local signature verification, not for signing itself.

Download the Chromium build Playwright drives, and its system libraries. Left out
of cloud-init because it's a ~195 MB download that takes ~20 minutes on this link:

```bash
PW=~/.local/share/mise/installs/npm-playwright-mcp/*/node_modules/playwright-core/cli.js
node $PW install --with-deps chromium
```

This is the one sanctioned apt install beyond the base set — Chromium's runtime
libraries (`libnss3`, `libgbm1`, `libasound2t64`, …) are exactly what mise cannot
provide. Playwright ships an `ubuntu26.04` dependency mapping, so `--with-deps`
resolves without hand-listing packages.

`install chromium` downloads two binaries, `chromium-1232` and
`chromium_headless_shell-1232`, and headless launches use the shell. An install
interrupted between them leaves a cache that looks populated but fails at launch
with "Executable doesn't exist" — re-run the same command, it skips what's there.
Budget ~1 GB and don't let the download run under a command timeout.

## Per-project apt packages

`megin` needs `pdftotext` to re-extract its programme data from the source PDF:

```bash
sudo apt-get install -y poppler-utils
```

Deliberately not in `cloud-init.yml`. It is a build-time dependency of one repo's
extraction script, not VM tooling, and only matters when re-running
`mise data:extract` — the generated JSON is committed, so the app builds without
it. mise has no backend that provides poppler.

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

## Blast radius

mimir runs `isolated: false`, `isolate_network: false`, `forward_ssh_agent:
true`. Nothing below is enforced; it's all convention.

- The Mac is mounted read-write at `/Users`, `/Applications`, `/Library`,
  `/Volumes`, `/private` and `/mnt/mac`. Work lives in `~/code`; repos from
  `/Users/deity/Code` get symlinked in as needed
- `mac` and `orb <cmd>` execute arbitrary commands on macOS; `orbctl` can
  delete or clone OrbStack machines, including this one
- The forwarded SSH agent is root on `fenrir`, `gromit`, `upright` and
  `nucleara`, and `tvararu` on GitHub — the widest reach of anything here
- `/dev/vdb1` is one pool shared with the Docker machine's volumes at
  `/mnt/machines`, so filling the VM's disk fills the Mac's
- `/mnt/machines/docker/volumes` is live service state (`gromit_data`,
  `typesense-demo_postgres-data`, kamal registry) — never written to
- The VM is case-sensitive, APFS is not

Destructive git in symlinked repos is explicitly fine — recovery is version
control's job. The exception is `git clean -fdx`, which also removes gitignored
`config/secret.key` and `.env` files that no commit can restore.

If a real boundary is ever wanted instead, the OrbStack isolation flags above
are the place to start — at the cost of the agent forwarding that makes commit
signing and GitHub access work.

## Docker

Not installed in the VM — huginn already runs Docker via OrbStack, and its
machines and volumes are visible at `/mnt/machines`.

## Claude config

`~/.claude/CLAUDE.md` inside the VM documents all of the above for Claude
itself. It's deliberately untracked and dies with the VM; this file is the
durable record.

The Playwright MCP is registered at user scope in `~/.claude.json`, pointing at
the mise shim rather than huginn's `npx @playwright/mcp@latest`:

```bash
claude mcp add --scope user playwright -- \
  /home/deity/.local/share/mise/shims/playwright-mcp --headless --browser chromium
```

mise owns the package (`npm:@playwright/mcp` in `~/.config/mise/config.toml`),
which pins the version and avoids npx re-resolving `@latest` over the network on
every server launch. `--headless` is not optional — there's no display here.

The path must be absolute. Claude's process runs without
`~/.local/share/mise/shims` on PATH (`~/.profile` adds it, but the session's
shell doesn't always source it), so a bare `playwright-mcp` dies with ENOENT.
Beware verifying this with `claude mcp add` and `claude mcp list` from a shell
where you've exported the shims yourself — the health check inherits that PATH
and reports a green the session cannot reproduce. Check with
`env -i PATH=<the session's PATH>` instead.

`--browser chromium` is not optional either, and is the one thing that differs
from huginn. The MCP server defaults to channel `chrome`, meaning real Google
Chrome at `/opt/google/chrome/chrome`; Google publishes no Chrome build for Linux
arm64, so that default can never be satisfied on this VM. The flag switches it to
Playwright's own bundled Chromium, which does ship arm64. It isn't listed in
`--help` (which advertises only chrome/firefox/webkit/msedge) but is accepted.

Changing the registration does not affect an already-running Claude session — the
MCP server process keeps the arguments it was spawned with. Reconnect via `/mcp`
or restart.

`~/.claude/settings.json` is seeded by cloud-init with `attribution` blanked, so
commits and PRs made from the VM carry no `Co-Authored-By: Claude`, no "Generated
with Claude Code" and no `Claude-Session` trailer. Matches huginn, which sets the
first two.
