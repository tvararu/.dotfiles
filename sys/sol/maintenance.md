# sol

`sol` is my home NAS.

## Storage layout

NVMe `/dev/nvme0n1` (system):

| Part | FS         | Size   | Mount   |
| ---- | ---------- | ------ | ------- |
| p1   | vfat (ESP) | 484 MB | `/boot` |
| p2   | ext4       | 18 GB  | `/`     |
| p3   | ext4       | 201 GB | `/home` |

ZFS pool **`pool`** (data) — `/mnt/pool`:

- **raidz1**, 3× Seagate IronWolf **ST8000VN002 8 TB** (by-id `…ZPV00LSG`, `…ZPV00MX0`, `…ZPV00NRZ`)
