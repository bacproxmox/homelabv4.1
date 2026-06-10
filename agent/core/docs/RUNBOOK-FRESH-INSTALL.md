# Homelab v2.3 Fresh Install Runbook

## 0) Proxmox fresh install sonrası tek komut

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bacproxmox/homelabv2.3/main/bootstrap.sh)
```

Reboot isterse aynı komutu tekrar çalıştır. Bootstrap sonunda install menu açılır.

## 1) Menüden ilk yapılacaklar

```text
1) Bootstrap secrets/env
2) Create Proxmox users
```

Bu aşama `/root/homelab-secrets`, `/root/homelab-logs`, `/root/homelab-state` yapısını hazırlar.

## 2) TrueNAS VM 101

Menüden `4) Install selected VM` > `101` seç veya:

```bash
cd /root/homelabv2.3
bash vm/101-truenas-vm-install.sh
```

Sonra manuel TrueNAS kurulumu:

1. `qm start 101`
2. VM console > installer içinde SADECE 64GB OS diskini seç
3. Kurulum bitince:
   ```bash
   qm stop 101
   qm set 101 --ide2 none
   qm set 101 --boot order=scsi0
   qm start 101
   ```
4. TrueNAS IP: `192.168.50.101`
5. Pool oluştur: `tank` + `private`
6. API key oluştur

## 3) TrueNAS dataset/share bootstrap

```bash
bash services/truenas/01-truenas-api-bootstrap-storage.sh
```

Not: ACL reset hâlâ bilinçli olarak manuel/yarı-manuel bırakıldı. API payload TrueNAS sürümüne göre değişebiliyor.

## 4) Ubuntu VM'ler

Menüden:

```text
3) Install all VMs except TrueNAS
```

Bu VM'leri oluşturur:

- 102 docker-arr
- 103 docker-network
- 104 nextcloud
- 105 homeassistant
- 106 docker-media / 32GB RAM / 512GB disk
- 107 chia-farmer / 16GB RAM / 320GB disk

## 5) VM106 iGPU passthrough

VM106 oluşturulduktan sonra, servislerden önce:

```bash
bash gpu/attach-igpu-to-vm106.sh
qm reboot 106
```

Kontrol:

```bash
bash maintenance/health/vm-resource-audit.sh
ssh bacmaster@192.168.50.106 'ls -lah /dev/dri || true'
```

## 6) Docker host hazırlığı

```bash
bash services/common/01-prepare-all-docker-hosts.sh
```

## 7) Core services

Menüden:

```text
6) Install core local services (Cloudflared auth yok)
```

Kurulan ana stackler:

- ARR stack: qBittorrent, Sonarr, Radarr, Prowlarr, Bazarr, FlareSolverr
- Jellyseerr
- Uptime Kuma
- Nextcloud
- Jellyfin
- Immich
- Ollama + Open WebUI
- Lidarr
- Home Assistant
- Cloudflared

## 8) İlk health check

```bash
bash maintenance/health/full-health-check.sh
bash maintenance/health/full-service-audit.sh
```

## 9) Service config phase

Bazı servislerde ilk web wizard/API key gerekir:

- Jellyfin: ilk admin + API key
- Jellyseerr: ilk login bağlantı akışı
- Immich: ilk admin akışı sürüme göre değişebilir

Sonra:

```bash
bash menu/config-menu.sh
```

veya install menu içinden:

```text
8) Phase 3 service configuration
```

## 10) SMTP / Chia / Maintenance

SMTP referansları:

```bash
bash config/smtp/01-write-service-smtp-reference.sh
bash maintenance/alerts/test-smtp-send.sh nextcloud
```

Chia farmer:

```bash
bash services/chia/01-chia-farmer-service-install.sh
```

Bakım menüsü:

```bash
bash menu/maintenance-menu.sh
```

## 11) Final kontroller

```bash
bash maintenance/health/audit-repo.sh
bash maintenance/health/vm-resource-audit.sh
bash maintenance/health/full-health-check.sh
bash maintenance/health/full-service-audit.sh
```

Support bundle:

```bash
bash maintenance/logs/collect-support-bundle.sh
```


14) Final Cloudflared remote access setup
- Run this at the end, after local services/config are complete. This is where Cloudflare browser auth may ask for interaction.
