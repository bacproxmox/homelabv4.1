# Homelab v2.4.5-r4

r4 is a careful stabilization pass based on the v2.4.5-r3 fresh install/support bundle.

## Main r4 changes

### Deterministic `nvme-vm-two`

- `nvme-vm-two` is still the standard storage for VM106 and VM107.
- If Proxmox storage `nvme-vm-two` already exists, the script exits successfully and never scans/wipes disks.
- If ZFS pool `nvme-vm-two` exists or is importable, the script imports/registers it with Proxmox.
- If an MLD/MDL M500 NVMe is detected by `/dev/disk/by-id`, sysfs, `lsblk -P`, or `nvme list`, r4 wipes it automatically and creates `nvme-vm-two` without an extra YES prompt.
- The script still refuses to wipe a root/boot disk.
- The generic single-unused-1TB fallback remains conservative and only runs when the disk has no children/signatures.

### Idempotent Proxmox users

- `bootstrap/01-create-proxmox-users.sh` now treats `already exists` as success.
- Re-running the guided pipeline repairs passwords/ACLs instead of stopping on existing users.

### PBS robustness

- PBS enterprise repo files are disabled before the first `apt-get update` in VM110.
- Deb822 `.sources` enterprise files are moved out of `sources.list.d` instead of relying only on `Enabled: no`.
- PBS API reachability accepts HTTP 200/401/403 as “proxy is alive”.
- NFS datastore mount remains timeout-bound to avoid long apparent freezes.
- PBS storage/job automation uses direct password handling and verifies `pvesm` storage creation.

### Chia installer UX

- Chia DB copy/import now uses `rsync --info=progress2` or `pv` when available.
- `.sqlite.gz` and `.tar.gz` imports stream with progress.
- Full SQLite `PRAGMA quick_check` is no longer the default for huge DB files. r4 performs a lightweight SQLite open/schema validation by default.
- Set `CHIA_DB_FULL_QUICK_CHECK=1` to force the old full check.
- Chia service startup now polls `chia show -s` / `chia farm summary` several times instead of taking a single early snapshot.

### Uptime Kuma

- The Chia Daemon monitor stays disabled because the Chia daemon normally listens on VM107 localhost only, not `192.168.50.107:55400`.

## Fresh install command

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bacproxmox/homelabv2.4.5/main/bootstrap.sh)
```
