# Homelab v2.3 Phase 3 Review

Checks run before packaging:

- `bash -n` against all shell scripts: OK
- executable bit on all `.sh`: OK
- `maintenance/health/audit-repo.sh`: OK

Design notes:

- Scripts are idempotent where practical.
- App APIs that are unstable across versions fail safely and print exact next steps.
- Jellyfin/Immich deep configuration uses optional API keys in `/root/homelab-secrets/*.env`.
