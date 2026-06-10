# Homelab v2.4.7

## Focus

v2.4.7 is the Cloudflared cleanup and qBittorrent policy release.

## Changes

- Restores early Cloudflared credential preparation on Proxmox.
- Uses stable Cloudflare Tunnel name: `homelab-main`.
- Keeps `cert.pem` only on Proxmox.
- VM103 final Cloudflared setup is JSON-only and does not run browser auth or DNS route commands.
- Replaces the fragile `cloudflared service install` flow with a simple systemd unit:
  - `Type=simple`
  - `TimeoutStartSec=0`
  - `Restart=always`
- Adds qBittorrent auto-configuration:
  - Maximum active downloads: 30
  - Maximum active uploads: 0
  - Maximum active torrents: 30
  - Upload speed limit: 1000 KiB/s
  - Stop/no-seed after completion using ratio/time seeding limits
  - SMTP notification attempt using Homelab SMTP secrets
- Keeps v2.4.6-r4 storage, TrueNAS, PBS, and Chia fixes.

## Test command

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bacproxmox/homelabv2.4.7/main/bootstrap.sh)
```
