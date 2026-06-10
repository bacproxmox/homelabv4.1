# Homelab v3.1.1-r2 - Support/Cloudflared Stabilization

This r2 build is a small stabilization rebuild over v3.1.1 based on the 2026-05-29 support bundle.

## Fixes

- Cloudflared final service no longer fails when `routes.env` / `api-routes.env` are missing from an upload; it carries `.defaults` copies and regenerates route files at runtime.
- Support bundle collection uses the backend script directly from the TUI and has task wrappers, so target resolution cannot return `127`.
- Support bundle script is defensive around missing commands and tar warnings.
- Profile/core-config aggregators now preserve real non-zero return codes instead of reporting false `:0` failures.
- Chia health check now passes `EXPECTED_CHIA_PLOT_DISKS` into VM107 and prints fstab/mount/block-device diagnostics when plot disks are missing.
- Version labels/state/log paths are updated for `v3.1.1-r2`.

## Notes

Cloudflare still uses the existing project model: `cloudflared tunnel login` + Proxmox `cert.pem` + tunnel UUID JSON. No Cloudflare API token is requested.
