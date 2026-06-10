# Homelab v2.4.4 Stabilization + Polish Update

## Confirmed fixes from v2.3.9 testing

- Nextcloud config scripts now include an install gate before OCC config.
  - If `occ status` reports `installed: false`, scripts run `maintenance:install` automatically.
  - If `/mnt/nextcloud/data/$NEXTCLOUD_ADMIN_USER` already exists, it is moved to a timestamped `.preinstall-backup-*` directory before install.
  - SMTP password output is redacted.
- Added maintenance cleanup script for old Nextcloud preinstall admin backups.
- Cloudflared ingress validate syntax fixed.
- Jellyfin viewer users now use `users.env` passwords (`ATLON_PASS`, `ELIFEZEL_PASS`, `TULUMBA_PASS`) instead of one random shared password.
- Seerr admin DB patch was strengthened to update matching local/Jellyfin rows across compatible schema variants.
- Lidarr integration was fixed:
  - root folder path uses `/media/music`.
  - Standard metadata and quality profile IDs are detected/used.
  - qBittorrent client uses Lidarr `QBittorrentSettings` payload and `musicCategory=lidarr`.
  - SQLite `database is locked` is handled with restart/wait/retry behavior.
  - HTTP 2xx is required before printing success.
- Prowlarr app sync is now validated by checking target app indexers after sync; category/test validation failures are WARN, not fake success.
- Chia install now uses hidden mnemonic input with 24-word validation and avoids logging the mnemonic.
- Chia DB bootstrap choices returned: fresh sync, HTTP/HTTPS URL, torrent/magnet, or manual VM107 file path.
- Bootstrap defaults no longer repeatedly prompt for fixed architecture values unless advanced override is selected.
- Uptime Kuma auto-config was restored: admin user and monitor injection are applied best-effort.
- Optional AdGuard Home installer added under `additionals/network/`.
- Sonarr/Radarr language policy script added for Turkish/German/English primary and Macedonian/Albanian lower-priority active languages.

## Notes

- Prowlarr indexer sync may still warn if an indexer returns no results for the target app categories. This is non-fatal and is reported clearly.
- The Sonarr/Radarr language policy relies on release-title language markers. Review Custom Formats and Quality Profiles in the UI before the final run.
