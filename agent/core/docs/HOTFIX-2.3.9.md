# Homelab v2.4.4

v2.4 stabilizasyon paketi, v2.3.8 testlerinden çıkan hotfixleri ana pakete alır ve Chia/maintenance tarafını güçlendirir.

## Dahil edilen confirmed fixler

- TrueNAS Nextcloud NFS bootstrap JSON fix ana scriptte.
- Cloudflared credentials JSON discovery/copy fix ana scriptte.
- Google OAuth fixed-v4 ana script olarak yerleştirildi.
- Jellyfin auto-wizard çalışır durumda tutuldu ve server name `Bacsflix` yapılır.
- Nextcloud app-code Docker named volume + `/mnt/nextcloud/data` TrueNAS tank bind mount mimarisi korunur.
- Nextcloud SMTP config ayrı script olarak geri getirildi.
- Prowlarr/FlareSolverr tag standardı `flaresolverr` yapıldı.

## Chia / VM107

- VM107 kurulumunda NVIDIA RTX + NVIDIA audio yanında JMicron/JMB/JMS58x SATA controller passthrough denenir.
- Yeni `maintenance/repair/repair-chia-plot-disks.sh` eklendi:
  - Toshiba HDWG180/HDWG480 plot disklerini by-id ile bulur.
  - `/mnt/chia-plots/disk1..disk6` mount/fstab hazırlar.
  - Chia binary için `/usr/local/bin/chia` symlink oluşturur.
  - `parallel_decompressor_count: 1` ayarlar.
  - Plot directory ekler ve farm summary doğrular.
- Health/audit scriptleri VM107 plot disk sayısı, mountlar, `nvidia-smi`, Chia daemon port `55400` ve compressed plot config kontrol eder.

## Maintenance güncellemeleri

- `repair-nextcloud-data-storage.sh` yeni Nextcloud mimarisine göre yeniden yazıldı.
- `repair-gpu-passthrough.sh` VM106 iGPU + VM107 NVIDIA + VM107 JMicron/Chia disk validasyonu yapar.
- `repair-nfs-mounts.sh` Nextcloud NFS preflight ve Chia mount görünürlüğü de kontrol eder.
- `collect-support-bundle.sh` `.env` ve secret değerlerini raw kopyalamaz; redacted ekler.
- `reinstall-selected-vm.sh`, VM104/106/107 sonrası ilgili repair/validation akışlarını tetikler.
