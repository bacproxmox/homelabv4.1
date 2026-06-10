# Homelab v2.4.5

## Root cause learned from v2.4.x comparison

v2.4.1 and the early v2.4.2/v2.4.3 builds created VM106/VM107 on the default `nvme-vm` storage. The five services that are down in the v2.4.4 dashboard are all VM106 services:

- Jellyfin `192.168.50.106:8096`
- Immich `192.168.50.106:2283`
- Lidarr `192.168.50.106:8686`
- Ollama API `192.168.50.106:11434`
- Open WebUI `192.168.50.106:3000`

v2.4.4 introduced a stricter dedicated storage expectation named `nvme-media`. On the tested install, `bootstrap/02-normalize-local-storage.sh` did not create `nvme-media`, so VM106 and VM107 were never created. Because the `run_required` helper captured the wrong exit code after a failed `if run ...`, it printed "critical failure" but returned `0`, allowing the pipeline to continue into service install/config and Uptime Kuma monitor creation for VMs that did not exist.

## v2.4.5 fixes

### Storage

- Removes the `nvme-media` storage standard.
- Creates/uses `nvme-vm-two` on the MLD M500 NVMe.
- VM106 uses `nvme-vm-two` with a default 512G disk.
- VM107 uses `nvme-vm-two` and calculates remaining safe capacity after VM106 and a free-space reserve.

### Pipeline safety

- `run_required` now returns the real failing exit code.
- The guided pipeline uses storage normalize as a required step.
- If `nvme-vm-two` cannot be created/found, the guided pipeline stops before VM/service phases.

### Dashboard accuracy

- Uptime Kuma disables optional VM106/VM107 monitors if the backing VM is absent, instead of creating permanent red monitors.

### Cloudflared

- Final VM103 Cloudflared setup skips `cloudflared tunnel route dns` when early Proxmox tunnel credentials were used. DNS routes are already created during early credential preparation, and VM103 intentionally does not receive `cert.pem`.

### PBS

- PBS installer disables PBS enterprise repositories more broadly.
- Existing datastore `.chunks` directories are treated as an idempotent recovery/import case rather than a fatal create error.
- PBS reachability validation uses `/api2/json/version` instead of HEAD on the UI root.

### Hardware preflight

- Adds a best-effort hardware preflight that highlights NVMe media errors, pending/uncorrectable sectors, high disk temperatures, and kernel disk bus errors before the long install proceeds.

## Important expected behavior

If the MLD M500 NVMe is absent, partitioned, mounted, already part of ZFS/LVM/RAID, or looks like the root disk, v2.4.5 refuses to wipe it. This is intentional. It is safer to stop than to wipe the wrong disk.


## v2.4.5-r2 early-stop fixes

- Fixed MLD M500 detection in `bootstrap/02-normalize-local-storage.sh`. The previous parser split `MODEL="MLD M500 NVMe SSD"` on spaces, so it read `TYPE` incorrectly and failed to find `/dev/nvme0n1` even though hardware preflight listed it correctly.
- Added `nvme-vm` ZFS import/register validation before VM creation. If a pool exists on disk but is missing from `/etc/pve/storage.cfg`, the script imports/adds it instead of letting VM creation fail later.
- Made `bootstrap/01-create-proxmox-users.sh` idempotent for reruns. Existing PAM users no longer stop the guided pipeline.
- Added a Cloudflared early-credential rerun guard so restarting the guided pipeline does not create another tunnel or spam duplicate DNS-route errors.
