# Homelab v2.4.4 Hotfix - Nextcloud NFS + Cloudflared Credentials

## Nextcloud

Fixes the restart loop caused by the official Nextcloud container attempting to `chown /var/www/html/data` on an NFS mount where TrueNAS denied ownership changes.

Changes:

- TrueNAS bootstrap now prepares `tank/nextcloud` and `tank/nextcloud/data` as UID/GID `33:33` for `www-data`.
- TrueNAS NFS share `/mnt/tank/nextcloud` uses `maproot_user=root` and `maproot_group=root` so VM104 can perform first-run ownership normalization.
- Nextcloud service installer performs a VM104 preflight:
  - `/mnt/nextcloud` must be mounted.
  - `/mnt/nextcloud/data` must pass `chown 33:33` and `chmod 750`.
  - Docker Compose will not start until this preflight passes.
- If preflight fails, the script prints direct TrueNAS repair instructions instead of allowing a restart loop.

Expected final state:

```text
/var/www/html       -> Docker named volume nextcloud_nextcloud_html
/var/www/html/data  -> 192.168.50.101:/mnt/tank/nextcloud/data
```

## Cloudflared

Fixes the fresh install/rollback case where a remote Cloudflare tunnel exists, but the local credentials JSON is missing.

Changes:

- Default tunnel name updated to `homelab-v239`.
- If a remote tunnel exists but `/etc/cloudflared/<uuid>.json` is missing, the installer no longer fails immediately.
- Interactive options are shown:
  - create a new versioned tunnel and re-route DNS records,
  - delete/recreate the same tunnel after confirmation,
  - abort and import credentials manually.
- Non-interactive default is to create a new versioned tunnel, avoiding destructive tunnel deletion.
- `config.yml` is written only after a local credentials JSON exists.
