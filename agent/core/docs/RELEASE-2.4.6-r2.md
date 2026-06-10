# Homelab v2.4.7

## Amaç

v2.4.7, v2.4.6 fresh testinde elle doğrulanan düzeltmeleri kalıcılaştıran stabilizasyon sürümüdür.

## Ana değişiklikler

- Guided fresh pipeline başında `nvme-vm` ve `nvme-vm-two` destructive olarak onaysız wipe/recreate edilir.
- `nvme-vm` artık VM101 aşamasına bırakılmaz; storage normalize aşamasında oluşturulur.
- `nvme-vm`: 2TB XPG SPECTRIX S40G NVMe.
- `nvme-vm-two`: MLD/MDL/M500 NVMe veya serial `7CBC0759131100037331`.
- Manual option 12 safe/register-only kaldı; destructive reset ayrı option 16 ve guided pipeline ile çalışır.
- `bootstrap/01-create-proxmox-users.sh` set -u/local variable bug ve existing user idempotency düzeltmeleriyle yenilendi.
- Bootstrap secrets/env başına encrypted `/root/homelab-secrets-backup-*.tar.gz.enc` import seçeneği eklendi.
- Secrets import formatı: `openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000`.
- PBS fingerprint/storage/job ve Chia DB import progress düzeltmeleri v2.4.6’dan korunur.

## Güvenlik notu

Guided fresh pipeline destructive storage reset yapar. Root/boot disk güvenlik freni korunur; TrueNAS passthrough HDD/plot disk/PBS NFS datastore hedeflenmez. Manual maintenance için safe option 12, destructive reset için option 16 kullanılmalıdır.
