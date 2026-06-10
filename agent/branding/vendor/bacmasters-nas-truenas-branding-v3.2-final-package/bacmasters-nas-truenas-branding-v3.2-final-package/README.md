# Bacmaster's NAS branding for TrueNAS SCALE — Homelab v3.2

Bu paket **TrueNAS SCALE WebUI** için hazırlanmıştır. Homelab v3.2'de şu menüye uygun:

`Additionals -> Branding -> Bacmaster's NAS`

> Not: Jellyfin için değildir. Jellyfin tarafında Bacsflix teması ayrı script olmalı.

## Çalıştırma

Paketi Proxmox hostuna gönderip aç:

```powershell
scp "$env:USERPROFILE\Downloads\bacmasters-nas-truenas-branding-v3.2-final-package.zip" root@192.168.50.100:/root/
ssh root@192.168.50.100 "cd /root && rm -rf bacmasters-nas-truenas-branding-v3.2-final-package && unzip -o bacmasters-nas-truenas-branding-v3.2-final-package.zip && cd bacmasters-nas-truenas-branding-v3.2-final-package && bash apply-bacmasters-nas-truenas-v3.2-final.sh"
```

Varsayılan hedef:

- TrueNAS: `192.168.50.101`
- SSH user: `/root/homelab-secrets/truenas-login.env` içinden, yoksa `truenas_admin`

Farklı IP ile:

```bash
TRUENAS_IP=192.168.50.101 bash apply-bacmasters-nas-truenas-v3.2-final.sh
```

## Status

```bash
bash status-bacmasters-nas-truenas-v3.2.sh
```

## Restore

```bash
bash restore-bacmasters-nas-truenas-v3.2.sh
```

## Güvenlik notları

Bu paket sadece TrueNAS WebUI statik loader tarafını değiştirir:

- `/usr/share/truenas/webui/index.html`
- `/usr/share/truenas/webui/bacmasters-brand/`

Şunlara dokunmaz:

- pool
- dataset
- share
- middleware ayarları
- kullanıcılar
- servisler
- diskler

TrueNAS güncellemeleri WebUI dosyalarını ezebilir. Güncelleme sonrası `apply` tekrar çalıştırılabilir.
