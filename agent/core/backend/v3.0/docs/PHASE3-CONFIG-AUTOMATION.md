# Homelab v2.3 Phase 3 - Config Automation

This phase adds post-install configuration scripts.

## Added

- `config/arr/00-export-arr-api-keys.sh`
- `config/arr/01-configure-arr-basics.sh`
- `config/prowlarr/01-add-canonical-indexers.sh`
- `config/jellyfin/01-jellyfin-libraries-and-users.sh`
- `config/jellyseerr/01-jellyseerr-config-readiness.sh`
- `config/nextcloud/02-nextcloud-smtp-google-and-users.sh`
- `config/immich/02-immich-users-smtp-external-library-note.sh`
- `config/ollama/01-openwebui-models-and-admin-note.sh`
- `menu/config-menu.sh`
- `maintenance/health/full-service-audit.sh`

## Important

Some apps change first-run / admin APIs frequently. For those apps, scripts are intentionally safe:
they validate API availability and skip with instructions instead of corrupting config.

Jellyfin and Immich should receive API keys after first-run admin setup:

- `/root/homelab-secrets/jellyfin.env`
- `/root/homelab-secrets/immich.env`

