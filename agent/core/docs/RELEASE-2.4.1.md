# Homelab v2.4.4 Stabilization Notes

v2.4.4 keeps the v2.4 architecture and focuses on reducing mid-install prompts, tightening health checks, and polishing services found during the v2.4 fresh install test.

## Main fixes

- Guided TrueNAS checkpoint now asks whether manual install is finished first, then automatically removes installer ISO/CD, sets disk boot, starts VM101, verifies WebUI, and loops until SSH is really reachable.
- Chia mnemonic, key label, DB bootstrap mode, and DB URL/path are collected during Bootstrap secrets/env. Chia install is intended to run non-interactively.
- Chia expected plot disks changed from 6 to 5 because the failed/removed Toshiba disk is no longer expected.
- Official Chia DB torrent default: `https://torrents.chia.net/databases/mainnet/mainnet.latest.tar.gz.torrent`.
- Uptime Kuma monitors: Proxmox and PBS now set TLS ignore, Nextcloud monitor uses local HTTP status endpoint.
- PBS first-stage config now disables enterprise repo, ensures no-subscription repo, updates/upgrades, and reboots if required.
- PBS audit no longer assumes `proxmox-backup-manager` is always available in PATH.
- Ollama model pull choices are collected during Bootstrap secrets/env and applied during install/config.
- Early Cloudflared credential preparation can run on Proxmox and later be used by VM103 final Cloudflared setup.
- Sonarr/Radarr language policy payload rebuilt to avoid invalid custom-format IDs and reduce HTTP 400 failures.
- Support bundle copy helper belongs to v2.4.4 maintenance menu.
- Support bundle excludes raw `chia-mnemonic.env` entirely.
