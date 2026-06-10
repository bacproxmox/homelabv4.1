# Homelab v3.1 Modular Release

## What changed

- Added `bin/homelab` as the stable runner interface.
- Added manifest-driven guided install in `installer/tui.sh`.
- Added `manifests/guided-steps.tsv` so guided install steps are data-driven.
- Added `lib/core`, `lib/proxmox`, `lib/truenas`, and `lib/remote` shared helpers.
- Added modular TrueNAS VM creation flow in `flows/truenas/create-vm.sh`.
- Added modular TrueNAS checkpoint/postinstall/storage flows under `flows/truenas`.
- Added disk health task split under `tasks/maintenance/health`.
- Preserved v3.0 backend under `backend/v3.0`.
- Converted legacy script entrypoints into thin wrappers.

## Important paths

```text
bin/homelab
installer/tui.sh
manifests/guided-steps.tsv
tasks/
flows/
lib/
backend/v3.0/
```

## Compatibility policy

Old script paths remain callable. v3.1 wrappers prefer modular replacements for TrueNAS and health checks, and use the preserved v3.0 backend for service/config behavior that was already working.
