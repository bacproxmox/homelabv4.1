# Homelab v2.4.4 Hotfix Rollup

This rollup collects the fixes found during the v2.3.14/v2.4 dry-run cycle without changing the VM/service architecture.

## Included

- Guided install pipeline stays intact and Cloudflared browser auth remains a final remote-access step.
- TrueNAS fixed-MAC/post-install/API-key workflow from the validated non-interactive helper remains included.
- Uptime Kuma v2 is forced to SQLite via `UPTIME_KUMA_DB_TYPE=sqlite` to avoid the first-run DB picker blocking automation.
- Bazarr announcement cleanup is broadened beyond the old single-table cleanup.
- Google OAuth auto-register prompt is auto-confirmed for one-button install; a maintenance script can disable it later.
- Nextcloud/Bacscloud:
  - Local LAN URL is explicitly `http://192.168.50.104:8080`; local HTTPS on `https://192.168.50.104:8080` is not expected.
  - `maintenance:mimetype:update-js` is no longer run automatically because it can trigger `INVALID_HASH` on `core/js/mimetypelist.js`.
  - Added maintenance repair for `core/js/mimetypelist.js` integrity warnings.
  - Cloudflare/proxy HTTPS overwrite is limited to proxy sources instead of blanket LAN clients.
  - HSTS header is configured best-effort inside the Nextcloud Apache container.
- Prowlarr canonical indexers are added before ARR app/indexer sync in run-all config flow.
- Chia DB `.tar.gz` import handling and `parallel_decompressor_count=1` remain included from previous v2.4 fixes.

## Notes

If Bacscloud is reachable via `cloud.bacmastercloud.com` but not `https://192.168.50.104:8080`, that is expected: direct LAN access is HTTP unless a separate local HTTPS reverse proxy is added.
