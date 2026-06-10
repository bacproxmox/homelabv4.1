# Homelab v2.4.4

Conservative stabilization release based on the known-good v2.4.1 VM/pipeline foundation.

## Core rule

v2.4.4 intentionally avoids changing the shared VM creation flow in `lib/vm-cloudinit-common.sh`. Fixes are isolated to service/config scripts and VM-specific storage selection.

## Included fixes

- Bacscloud Admin Overview cleanup: HSTS, trusted domains, appdata/theming repair, AppAPI warning cleanup, cron/background jobs, branding polish.
- Bacscloud Social Login + controlled Registration: Google provider setup, pending/users groups, quota policy, secret-safe logging.
- Uptime Kuma v2 auto-config: SQLite preselect, Proxmox/PBS self-signed TLS-ignore, Chia monitor disabled until Chia is installed.
- Chia DB bootstrap: official torrent default, tar.gz stream import, zero-byte/invalid DB rejection, mnemonic not logged and removed after successful key import.
- TrueNAS Chia DB cache: `/mnt/tank/chia-db` dataset/NFS/SMB; VM107 mounts it as `/mnt/chia-db-cache`; downloads/cache stay on TrueNAS while active DB stays local.
- PBS: real `proxmox-backup-server` installation, `BACKUP_PASS` root/PAM password setup, 8007 validation, backup datastore/job automation hooks.
- Immich: `/dev/dri` is optional; CPU fallback starts the service when GPU device nodes are missing.
- Support bundles: stronger secret redaction for OAuth/clientSecret/GOCSPX/token patterns.
- Storage: optional `nvme-media` storage on the blank MLD M500 1TB NVMe; VM106 and VM107 default there.
