# Homelab v3.2 - Bacsflix Jellyfin Branding

Bu paket, yeni kurulmuş Homelab Jellyfin kurulumunu görsel olarak **Bacsflix** markasına çevirir.

Hedef mimari:

- Proxmox host: `root@192.168.50.100`
- Jellyfin VM: `192.168.50.106`
- Jellyfin container: otomatik tespit edilir (`hb-jellyfin`, `jellyfin`, veya adında `jellyfin` geçen container)
- Jellyfin URL: `http://192.168.50.106:8096/web/`

## Repo içine önerilen konum

Homelab v3.2 repo içinde bu klasörü koruyarak ekle:

```text
backend/v3.0/additionals/branding/bacsflix-jellyfin/
```

v3.2 repo backend klasörünü ayrıca `backend/v3.2` diye ayırırsan aynı klasörü oraya da taşıyabilirsin. Script kendi konumuna göre assetleri bulur.

## Kullanım

Proxmox üzerinde, repo root içinden:

```bash
bash backend/v3.0/additionals/branding/bacsflix-jellyfin/20-apply-bacsflix-jellyfin-branding.sh apply
```

Durum kontrolü:

```bash
bash backend/v3.0/additionals/branding/bacsflix-jellyfin/20-apply-bacsflix-jellyfin-branding.sh status
```

Geri alma:

```bash
bash backend/v3.0/additionals/branding/bacsflix-jellyfin/20-apply-bacsflix-jellyfin-branding.sh restore
```

## Ne yapar?

- Jellyfin login ekranına Bacsflix arka planını uygular.
- Üst sol Jellyfin logosunu Bacsflix wordmark ile değiştirir.
- Login sonrası ana arayüzü kırmızı/sinematik Bacsflix temasına çeker.
- Browser tab title/favicons için Bacsflix override uygular.
- Jellyfin media/config/database dosyalarına dokunmaz.
- Orijinal `index.html` ve eski branding dosyalarını yedekler.

Yedekler VM106 üzerinde tutulur:

```text
/opt/homelab/jellyfin/branding/bacsflix/backups/
```

## Guided Install entegrasyonu

Bu script, Jellyfin container ayağa kalktıktan sonra çalıştırılmalı. En uygun sıra:

1. VM106 media/AI kurulumu
2. Jellyfin container kurulumu
3. Jellyfin ilk kullanıcı/kütüphane config adımı
4. `20-apply-bacsflix-jellyfin-branding.sh apply`

Jellyfin container güncellenirse veya web dosyaları sıfırlanırsa aynı `apply` komutu yeniden çalıştırılabilir.
