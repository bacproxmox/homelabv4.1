# Homelab v2.4.4 PBS VM110 hotfix

Adds a dedicated Proxmox Backup Server VM:

- VMID: `110`
- Name: `pbs-backup`
- IP: `192.168.50.110`
- MAC: `02:23:14:00:01:10`
- Web UI: `https://192.168.50.110:8007`
- Cloudflare routes: `pbs.bacmastercloud.com`, `pbs-api.bacmastercloud.com`

Implementation notes:

- VM110 uses the same Proxmox cloud-init flow as the other Linux VMs, but uses a Debian 13/Trixie cloud image because Proxmox Backup Server is officially installed on Debian using the Proxmox Backup Server APT repository.
- `bootstrap/00-bootstrap-secrets.sh` now asks for `BACKUP_PASS` instead of reusing `BACMASTER_PASS`.
- `services/pbs/01-pbs-service-install.sh` installs `proxmox-backup-server`, creates/updates `backup@pam`, grants admin ACL, and creates a small default datastore at `/backup/datastore/homelab`.
- The datastore is intentionally a starter/default on the VM disk; long-term backup storage can later be moved to a larger dedicated disk or TrueNAS/NFS-backed path.
