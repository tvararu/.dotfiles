# luna

`luna` is an Ubuntu 26.04 VM running under Incus on `sol`. It exists so Claude
can run with `--dangerously-skip-permissions` without doing so on the NAS itself.
It is sol's counterpart to `mimir` (OrbStack on huginn) and `openhubris` (Incus
on t1).

## Create

The Incus host is configured once from `sys/sol/incus-preseed.yml`. Then:

```bash
cd ~/.dotfiles
incus init images:ubuntu/26.04/cloud luna --vm
incus config set luna limits.cpu=2 limits.memory=4GiB
incus config set luna boot.autostart=true boot.autostart.delay=30
incus config device override luna root size=40GiB
incus config set luna cloud-init.user-data="$(cat sys/luna/cloud-init.yml)"
incus start luna
```

`cloud-init.user-data` must be set before the first boot. `description` is a
property (`incus config set luna --property description=…`), not a config key.

## Sizing

sol has 6.9 GiB of RAM and 4 cores, shared with Jellyfin and ZFS.
2 vCPU / 4 GiB leaves the host two cores and ~2.9 GiB.

ZFS ARC is capped at 1 GiB in `/etc/modprobe.d/zfs.conf`. Without it ARC's
default ceiling is ~5.9 GiB and it will contend with qemu for memory.

Storage is the `dir` driver on `/home/incus`, on the NVMe. `/` is only 18 GB, and
the ZFS pool is raidz1 on spinning disks — the wrong medium for compile
workloads. Instances are disposable; `cloud-init.yml` is the durable record, so
losing snapshots costs nothing.

## Isolation

Deliberately stronger than mimir, which mounts the Mac read-write at `/Users`.

- A virtual machine, not a container: its own kernel behind the KVM boundary.
- **No host filesystem passthrough.** `virtiofsd` is not installed, so `/mnt/pool`
  cannot be shared into the guest even by accident.
- **No `openssh-server`, no `authorized_keys`.** Tailscale SSH is a complete SSH
  server inside `tailscaled` that claims port 22 on the Tailscale IP alone, so
  luna listens on nothing reachable from sol's bridge and stores no static keys.
- **Reachability is identity, not routing.** sol's ufw permits only DNS/DHCP
  inbound on `incusbr0` plus internet egress; the LAN, sol's own services and the
  tailnet CIDR are denied.

Two things that are easy to get wrong here:

- The tailnet block **must** be an Incus network ACL (`luna-noroute`), not a ufw
  rule. Tailscale inserts `-j ts-forward` at the head of FORWARD, and its ACCEPT
  for `-o tailscale0` preempts every ufw rule that follows. The ACL drops at the
  bridge, before forwarding happens. A ufw `route deny` to `100.64.0.0/10` looks
  correct and silently does nothing.
- ufw's `before.rules` accept ICMP echo in FORWARD unconditionally, so luna can
  ping LAN hosts even though it cannot open TCP or UDP to them. Ping is not a
  valid test of these rules.

## Never stop luna

**Do not `incus stop luna`, ever.** It runs long-lived `claude remote-control`
sessions that do not survive a shutdown, and it is routinely under real load with
work in flight. `boot.autostart=true` exists to bring it back after a host reboot,
not as licence to restart it. If sol needs resources, take them from somewhere
else — check `incus exec luna -- uptime` before assuming it is idle.

## Access

- `incus exec luna -- <cmd>` from sol. This runs over vsock, so it survives any
  network or firewall misconfiguration — it is the recovery path.
- `ssh deity@luna` over the tailnet, after `tailscale up --ssh --hostname=luna`.
  Tailscale SSH also needs an `ssh` rule in the tailnet policy file; a network
  grant alone is not sufficient. The local account must exist with a real shell
  and home, which `cloud-init.yml` provides.

## Tooling

`cloud-init.yml` follows mimir's rule: apt provides only what mise cannot (git,
`build-essential` for rust's linker, `unzip` for bun), plus jq/ripgrep/htop,
which are not worth compiling on 2 vCPUs. mise owns bun, node, rust and uv.

`~/code/openhubris` holds the stow-managed config from the t1 VM. Only the `git`
package is stowed and `claude/.claude/settings.json` copied across — that repo's
`CLAUDE.md` describes t1's hardware and virtiofs model mounts, and its mise
config expects gocryptfs volumes and age keys that do not exist here.
