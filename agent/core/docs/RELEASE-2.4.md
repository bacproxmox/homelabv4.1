# Homelab v2.4.4 Hotfix / Stabilization Notes

## TrueNAS post-install automation

v2.4 integrates the tested TrueNAS post-install helper flow on top of v2.3.13.

### Confirmed working flow

1. Install Menu option 1 now asks for the TrueNAS `truenas_admin` SSH password and writes:
   - `/root/homelab-secrets/truenas-login.env`
2. VM101 is created with a fixed MAC address:
   - `02:23:14:00:01:01`
3. Recommended router DHCP reservation:
   - `02:23:14:00:01:01 -> 192.168.50.101`
4. After manual TrueNAS install, enable SSH from WebUI:
   - Allow Password Authentication: ON
   - Password Login Groups: `builtin_administrators` or the admin group for `truenas_admin`
   - Start SSH
5. Install Menu option 4 automatically runs the TrueNAS post-install helper if `/root/homelab-secrets/truenas-api.env` is missing.
6. The helper:
   - stops VM101
   - removes the ISO/CD-ROM
   - sets boot order to `scsi0`
   - starts VM101
   - waits for 192.168.50.101, with DHCP/MAC scan fallback
   - imports pools using the confirmed command form without `-job`:
     - `sudo midclt call pool.import_find`
     - `sudo midclt call pool.import_pool '{"guid":"14345028207300573632"}'`
     - `sudo midclt call pool.import_pool '{"guid":"728378451231267446"}'`
   - creates a TrueNAS API key
   - writes `/root/homelab-secrets/truenas-api.env`
   - writes a legacy compatibility `/root/homelab-secrets/truenas.env`
   - applies final DNS/network settings and reboots TrueNAS

### DNS defaults

- Primary DNS: `192.168.50.1`
- Secondary DNS: `192.168.50.1`
- Tertiary DNS: `1.1.1.1`

### API key behavior

Install Menu option 4 no longer asks for a TrueNAS API key. It loads:

```bash
/root/homelab-secrets/truenas-api.env
```

If missing, option 4 offers to run the post-install helper first.

## Fixed VM MAC plan

Cloud-init VMs now default to stable locally administered MAC addresses:

| VMID | Role | MAC | IP |
|---:|---|---|---|
| 101 | TrueNAS | `02:23:14:00:01:01` | `192.168.50.101` |
| 102 | docker-arr | `02:23:14:00:01:02` | `192.168.50.102` |
| 103 | docker-network | `02:23:14:00:01:03` | `192.168.50.103` |
| 104 | Bacscloud / Nextcloud | `02:23:14:00:01:04` | `192.168.50.104` |
| 105 | Home Assistant | `02:23:14:00:01:05` | `192.168.50.105` |
| 106 | docker-media / AI | `02:23:14:00:01:06` | `192.168.50.106` |
| 107 | Chia farmer | `02:23:14:00:01:07` | `192.168.50.107` |
| 110 | PBS backup | `02:23:14:00:01:10` | `192.168.50.110` |

Router DHCP reservations are still recommended, especially for VM101 before SSH is enabled.


## Guided full install pipeline

Install Menu now includes option `0) Guided full install pipeline (1→9 + final Cloudflared, TrueNAS manuel duraklı)`. This is only an orchestrator: it calls the existing menu scripts in order and keeps the required manual checkpoint between TrueNAS VM installation and the TrueNAS post-install/API/storage flow. After the manual TrueNAS install and SSH enablement, it continues through storage bootstrap, VM102-107 creation, Docker host preparation, core local service install, basic config, core service config, SMTP/Uptime Kuma/Chia, then runs Cloudflared remote access setup as a final interactive step before health checks. Cloudflared browser authentication is intentionally moved out of the core service install phase so the pipeline does not block early on a Cloudflare auth URL.


### VM110 PBS Backup

VM110 `pbs-backup` is added as a dedicated Proxmox Backup Server VM. It uses the same cloud-init workflow, fixed MAC `02:23:14:00:01:10`, and IP `192.168.50.110`. The base image is Debian 13/Trixie so PBS can be installed from the official Proxmox Backup Server APT repository.
