# Homelab v2.4.6

v2.4.6 is the stabilization release that permanently integrates the working hotfixes proven during the v2.4.5-r4 fresh-install tests.

## Main goals

- Make `nvme-vm-two` creation deterministic on the MLD/MDL/M500 NVMe.
- Make Proxmox user creation fully idempotent.
- Make PBS setup complete without manual enterprise-repo/fingerprint repair.
- Make Chia DB import visible and avoid long silent validation.

## Key fixes

### Storage / `nvme-vm-two`

`bootstrap/02-normalize-local-storage.sh` now:

- skips wipe/scanning if `nvme-vm-two` already exists;
- registers an existing `nvme-vm-two` ZFS pool if only the Proxmox storage entry is missing;
- detects the target disk using sysfs, `/dev/disk/by-id`, model, serial and the known MLD M500 serial `7CBC0759131100037331`;
- auto-wipes the detected MLD/MDL/M500 target disk without another confirmation;
- keeps the root/boot disk safety brake.

### User creation

`bootstrap/01-create-proxmox-users.sh` treats existing Linux/PAM/Proxmox users as success and still repairs passwords, enabled state, roles and ACLs.

### PBS

PBS is now handled in two clean phases:

1. `services/pbs/01-pbs-service-install.sh` configures VM110, disables enterprise PBS sources before any apt update, mounts the Raspberry Pi NFS datastore with timeout, and registers/reuses the PBS datastore idempotently.
2. `config/pbs/01-pbs-backup-automation.sh` obtains the PBS certificate fingerprint from Proxmox, adds `pbs-pi-a` with fingerprint, verifies `pvesm status`, and creates/updates the `homelab-daily-pbs` job.

HTTP `200`, `401`, and `403` all count as PBS proxy reachable. Fingerprint is mandatory for adding PBS storage.

### Chia

Chia DB import now uses progress-capable copy/decompress helpers and defaults to lightweight SQLite validation. Full `PRAGMA quick_check` can be enabled with `CHIA_DB_FULL_QUICK_CHECK=1`.

### Uptime Kuma

The Chia daemon monitor stays disabled because Chia daemon normally listens on VM107 localhost only, not on `192.168.50.107:55400`.

## Fresh install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bacproxmox/homelabv2.4.7/main/bootstrap.sh)
```
