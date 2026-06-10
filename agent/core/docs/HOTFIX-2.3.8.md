# Homelab v2.4.4 Stabilization Hotfix

## Goal

v2.4 focuses on stabilizing the fresh install pipeline after v2.3.7 field testing:

- GPU-aware VM creation and service install
- Jellyfin first-run wizard automation/gate before Seerr
- Nextcloud container/storage architecture fix
- Better readiness checks and repair paths
- Rollback/checkpoint tooling for faster test cycles

## Key changes

### GPU passthrough

- VM106 now attempts to attach the Intel iGPU automatically.
- VM107 now attempts to attach the NVIDIA GPU automatically, plus the NVIDIA audio function when present.
- `maintenance/repair/repair-gpu-passthrough.sh` validates/repairs GPU passthrough and driver state.
- Prepare Docker hosts calls GPU repair/validation after VM prep.
- Jellyfin and Ollama compose files only mount `/dev/dri` if it actually exists.

### Jellyfin readiness

- Jellyfin config first tries to complete the startup wizard automatically.
- If automatic wizard completion fails, it pauses with a clear manual gate.
- Seerr should not run successfully until Jellyfin login and libraries are ready.

### Nextcloud architecture

- Nextcloud no longer bind-mounts an empty host folder over `/var/www/html`.
- App code lives in a Docker named volume.
- User data mounts to `/mnt/nextcloud/data`, backed by TrueNAS `/mnt/tank/nextcloud/data`.
- Nextcloud config scripts verify `version.php` and avoid OCC calls during restart loops.

### Checkpoints

- Added `maintenance/checkpoints/rollback-checkpoints-menu.sh`.
- Supports TrueNAS-only rollback and VM snapshots at key stages.

## Suggested test flow

1. Bootstrap secrets/env
2. Create Proxmox users
3. Install TrueNAS VM101
4. Bootstrap TrueNAS storage + install all VMs except TrueNAS
5. Prepare all Docker hosts
6. Install core services
7. Configure / repair basics
8. Phase 3 service configuration

If a stage works, use Maintenance > Rollback / Checkpoints to save it.
