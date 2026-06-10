# Homelab BacPhotos Immich Title Fix v6

This hotfix runs on Proxmox, connects to VM106, and patches Immich web/server runtime assets so browser tab titles change from `... - Immich` to `... - BacPhotos`.

Modes:

```bash
bash apply-bacphotos-immich-title-fix-v6.sh apply
bash apply-bacphotos-immich-title-fix-v6.sh status
bash apply-bacphotos-immich-title-fix-v6.sh restore
bash apply-bacphotos-immich-title-fix-v6.sh discover
```

Backups are stored on VM106 under:

```text
/opt/homelab/immich/branding/bacphotos/backups/
```

This is a direct container runtime asset patch. Reapply it after Immich container recreation/update.
