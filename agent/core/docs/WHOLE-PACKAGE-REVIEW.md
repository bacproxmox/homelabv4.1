# Homelab v2.3 Whole Package Review

Bu review paket tamamı için yapılmıştır: bootstrap -> secrets -> VM -> services -> config -> maintenance.

## Kontrol edilenler

- Bash syntax: tüm `.sh` dosyaları `bash -n` ile kontrol edildi.
- Executable bit: tüm scriptler çalıştırılabilir yapıldı.
- Menü referansları: `install-menu`, `config-menu`, `maintenance-menu` içindeki çağrılar mevcut dosyalarla eşleştirildi.
- Klasör standardı: `bootstrap`, `vm`, `services`, `config`, `menu`, `utils`, `maintenance`, `lib`, `docs`, `gpu`.
- Docker standardı: `/opt/homelab`, external network `homelab`, container prefix `hb-`.
- VM kaynakları: Homelabv4.1 dynamic RAM profil ile VM106 `65536 MB` max / `32768 MB` balloon, VM107 `8192 MB` sabit.
- Secrets standardı: `/root/homelab-secrets` ve güvenli env yazımı.

## Review sırasında düzeltilenler

1. Eksik Uptime Kuma servis installer eklendi: `services/uptime-kuma/01-uptime-kuma-service-install.sh`.
2. Eksik Home Assistant servis installer eklendi: `services/homeassistant/01-homeassistant-service-install.sh`.
3. Install menu core services sırası Uptime Kuma ve Home Assistant dahil olacak şekilde güncellendi.
4. Docker host hazırlığı VM105'i de kapsayacak şekilde güncellendi.
5. Maintenance docker cleanup artık Proxmox üzerinde lokal Docker aramak yerine remote VM'lerde çalışıyor.
6. Nextcloud SMTP config, `ZOHO_NEXTCLOUD_APP_PASS` değerini doğru şekilde kullanacak hale getirildi.
7. Nextcloud/Jellyfin/Immich configlerinde özel karakterli şifre/API key için remote env dosyası yöntemi kullanıldı.
8. Remote geçici env dosyaları config sonrası silinecek şekilde güncellendi.
9. TrueNAS disk by-id pathleri bulunamazsa script artık mevcut `/dev/disk/by-id` listesini gösterip doğru yolu soruyor.
10. `load_all_env` artık `hardware.env`, `truenas.env`, `arr-api.env`, `jellyfin.env`, `immich.env` dosyalarını da okuyabiliyor.
11. Cloud-init password bloğu özel karakterlere daha dayanıklı `chpasswd list` formatına alındı.
12. Health/audit scriptleri Uptime Kuma ve Home Assistant kontrollerini de kapsayacak şekilde güncellendi.
13. Fresh install runbook core service listesi güncellendi.

## Bilerek manuel kalanlar

- TrueNAS OS kurulumu.
- TrueNAS pool oluşturma: `tank` ve `private`.
- TrueNAS ACL reset/izinlerin UI üzerinden doğrulanması.
- Jellyfin ilk admin wizard ve API key oluşturma.
- Immich ilk admin/API key/external library UI doğrulaması.
- Jellyseerr ilk login ve Jellyfin bağlantı wizard kontrolü.
- Cloudflare Zero Trust route/policy tarafı dashboard doğrulaması.

## Final audit sonucu

```text
✅ Bash syntax OK
✅ Executable scripts OK
✅ Eski starter naming yok
✅ Required directories OK
✅ Core bootstrap exists
✅ Required service installers OK
✅ Repo audit temiz
```
