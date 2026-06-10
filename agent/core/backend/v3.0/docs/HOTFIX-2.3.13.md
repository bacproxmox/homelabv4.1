# Homelab v2.4.4 Hotfix Notes

v2.4 is a stabilization hotfix based on the v2.3.12 fresh-install logs.

## Fixed / changed

- Jellyfin post-config no longer auto-creates `Orhan` by default.
  - Default viewer users are now only `Elifezel`, `Atlon`, and `Tulumba`.
  - This avoids `ORHAN_PASS` / heredoc variable expansion failures under `set -u`.
- Config Menu `Run all core config scripts` now keeps running remaining config scripts after one failure and prints a final failure summary.
- Uptime Kuma service install now pins v2:
  - `louislam/uptime-kuma:2.3.2`
  - takes a data backup before changing/recreating an existing container.
- SMTP defaults updated to the confirmed Zoho EU Pro configuration:
  - Host: `smtppro.zoho.eu`
  - Port: `465`
  - Security: `SSL/TLS`
  - Username/from: `admin@bacmastercloud.com`
- Bacscloud production hardening added:
  - admin profile email/display name is set automatically,
  - SMTP is applied with password redaction,
  - background jobs are switched to cron,
  - `/etc/cron.d/homelab-nextcloud` is written,
  - maintenance window/default phone region/locale/timezone are set,
  - DB/mimetype repair commands are run,
  - visible branding is set to `Bacscloud` via theming.
- Chia DB bootstrap UX improved:
  - torrent/download path is persistent: `/home/bacmaster/chia-db-download`,
  - aria2 progress is visible in the terminal and logged to `aria2.log`,
  - resume is enabled with `aria2c -c`,
  - `.tar.gz` / `.tgz` DB archives are supported,
  - compressed plot decompressor count is forced to `1`.
- Chia health check now counts mounted `/mnt/chia-plots/disk*` paths rather than raw `/dev/disk/by-id` matches.
- Prowlarr canonical indexers no longer try known Cloudflare-heavy/problematic definitions by default (`magnetcat`, `kickasstorrents-ws`, `eztv`).

## Fresh install command

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bacproxmox/homelabv2.4.4/main/bootstrap.sh)
```

## Notes

- Direct LAN access to Bacscloud via `http://192.168.50.104:8080` can still show HTTPS/HSTS warnings because it is not the public Cloudflare HTTPS hostname. Use `https://cloud.bacmastercloud.com` for the clean production path.
- Chia torrent DB download may be very large. During the download, watch:

```bash
tail -f /home/bacmaster/chia-db-download/aria2.log
watch -n 10 'du -sh /home/bacmaster/chia-db-download; ls -lh /home/bacmaster/chia-db-download | tail'
```
