# Homelab v2.3 - Phase 4 Infra / Maintenance

Bu fazın amacı kurulum sonrası eksik kalan temel otomasyonları tamamlamaktır.

## Eklenenler

- TrueNAS API storage bootstrap
- Chia farmer kurulumu
- SMTP test helper
- Uptime Kuma SMTP not/helper
- VM resource audit
- VM106/VM107 resize repair
- Maintenance menu
- Ubuntu-only VM reset helper

## TrueNAS

Script:

```bash
bash services/truenas/01-truenas-api-bootstrap-storage.sh
```

Oluşturmayı dener:

- users/groups: media, bacmaster, tulumba
- datasets:
  - tank/media
  - tank/media/downloads/torrents
  - tank/media/movies
  - tank/media/series
  - tank/photos/immich-upload
  - private/photos
  - private/documents
- NFS shares
- SMB shares

ACL işlemleri TrueNAS sürümüne göre değiştiği için şimdilik güvenli not verir; ACL reset manuel doğrulanmalıdır.

## Chia

Script:

```bash
bash services/chia/01-chia-farmer-service-install.sh
```

- VM107 üzerinde Chia source install yapar.
- Mnemonic geçici `/root/homelab-secrets/chia.env` içine alınır.
- Kurulum sonunda `shred -u` ile silinir.
- `chia-farmer.service` systemd servisi oluşturulur.

## SMTP

```bash
bash config/smtp/01-write-service-smtp-reference.sh
bash maintenance/alerts/test-smtp-send.sh nextcloud
bash maintenance/alerts/test-smtp-send.sh immich
bash maintenance/alerts/test-smtp-send.sh jellyseerr
bash maintenance/alerts/test-smtp-send.sh uptime-kuma
bash maintenance/alerts/test-smtp-send.sh truenas
```

## Maintenance Menu

```bash
bash menu/maintenance-menu.sh
```

