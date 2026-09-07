# Task 1 — node2 prerequisites (measured 2026-09-07)

## Host

| Fact | Value |
|---|---|
| Hostname | `node2` (`node2.lan`) |
| Kernel | Linux 6.1.115-vendor-rk35xx |
| Architecture | **aarch64 / arm64** (Rockchip RK35xx SBC) |
| CPU | 8 cores |
| Memory | 15 GiB total, ~11 GiB available |
| SSH user | `hdd`, key-based, no password prompt |

**Architecture is the significant finding.** node2 is an ARM64 single-board
computer, not x86. Every image in the stack was checked for an `arm64` build
before the plan proceeded.

## Docker

| Fact | Value |
|---|---|
| Server | 29.6.2 |
| Server arch | arm64 |
| Compose | v2.26.1-4 |
| Usable without sudo | **Yes** — `hdd` is in the docker group |

### arm64 image availability (verified via `docker manifest inspect`)

| Image | arm64 |
|---|---|
| `wordpress:6-php8.3-apache` | yes |
| `mariadb:11` | yes |
| `favonia/cloudflare-ddns:latest` | yes |
| `alpine:latest` | yes |

No image substitutions required.

## Disk

`/` and `/opt` are both on `/dev/nvme0n1p1`: 908 GB total, **527 GB available**
(42% used). Far beyond the 10 GB the plan requires.

## Ports

| Port | State |
|---|---|
| 8080 | **free — selected as `WP_HOST_PORT`** |
| 8081 | busy |
| 8090 | free |

## NAS backup path

`/media/assets` is an NFS mount: `192.168.4.89:/volume1/Assets` (nfs4, rw). It
is the same Synology share the operator Mac mounts as `/Volumes/Assets`, which
is why `observability/` appears at `/Volumes/Assets/server/workspace/` there and
`/media/assets/server/workspace/` here.

- `/media/assets` itself is **not** writable by `hdd` (root-owned, `drw-r-xr-x`).
- `/media/assets/server` is `drwxrwxrwx`, so subdirectories can be created.
- `/media/assets/server/backup/wordpress` **did not exist**; created during this
  task and confirmed writable, owned `hdd:hdd`.

Backup destination for Task 13 is therefore `/media/assets/server/backup/wordpress`,
as specified. No blocker.

## Promtail

- Container command: `-config.file=/config/promtail-node2.yml`
- Host path to edit in Task 2 Step 9:
  `/opt/observability/promtail/config/promtail-node2.yml`
- Per-node config files exist for enigma, mindgate, node1, node2, node3,
  raspi2, seshat.

## Required binaries

`git`, `rsync`, `curl`, `tar`, `gzip` all present.

## Deviation from plan: sudo

**Passwordless sudo is NOT available for `hdd`.**

Docker needs no sudo, so Tasks 2, 5, 6, 7, 8, 9 are unaffected. But installing
systemd units in Tasks 10 and 13 does, and those steps use non-interactive
`ssh`, which cannot answer a password prompt.

Options at Task 10:

1. Run the systemd install steps with `ssh -t` so the password can be typed
   interactively. Two commands, twice.
2. Use a user-level timer (`systemctl --user`) instead, which needs no sudo but
   requires lingering enabled for `hdd` and does not survive as cleanly.
3. Grant `hdd` a narrowly scoped sudoers entry for `systemctl`.

Recommendation: option 1. It is two interactive commands during setup and
introduces no standing privilege.
