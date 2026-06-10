# BacsCloud Nextcloud Branding - Homelab v3.2

Run from the Proxmox host as root, normally `root@192.168.50.100`.

Target defaults:

- VM104: `192.168.50.104`
- Nextcloud container: `hb-nextcloud`
- Brand name: `BacsCloud`
- Slogan: `Your data. Your control.`
- Primary color: `#008CFF`
- URL: `https://cloud.bacmastercloud.com`

## Apply

```bash
cd additionals/branding
chmod +x 30-apply-bacscloud-nextcloud-branding.sh
bash 30-apply-bacscloud-nextcloud-branding.sh apply
```

## Status

```bash
bash additionals/branding/30-apply-bacscloud-nextcloud-branding.sh status
```

## Restore common defaults

```bash
bash additionals/branding/30-apply-bacscloud-nextcloud-branding.sh restore-default
```

## Notes

- This script uses Nextcloud `occ theming:config`.
- It does not edit Nextcloud core files.
- Assets are copied into the Nextcloud container before calling `occ`, which avoids the container path issue seen in the first wallpaper test.
- Browser cache may need `Ctrl+F5` after applying.
