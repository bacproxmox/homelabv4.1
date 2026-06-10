# Homelab v2.4.4 Hotfix

Ana hedef: v2.3.6 gerçek testlerinden çıkan servis/config buglarını toparlamak.

## Büyük değişiklikler

- Nextcloud fresh install artık `/mnt/tank/nextcloud/data` üzerinden TrueNAS tank kullanır.
- Existing Nextcloud local-data düzeltmesi için `maintenance/repair/repair-nextcloud-data-storage.sh` eklendi.
- Immich mount doğrulaması blocking hale getirildi; `/mnt/tank/photos` ve `/mnt/private/photos` mount değilse external library oluşturulmaz.
- Immich service isimleri güncellendi: `database`, `redis`, `immich-machine-learning`, `immich-server`.
- Seerr service permissions düzeltildi; `/app/config/logs` EACCES için `/opt/homelab/seerr` owner normalize edilir.
- Seerr scan jobları VM102 remote block içinde tetiklenir; Proxmox host üzerinde `/opt/homelab/seerr/config/settings.json` aranmaz.
- Core config menüsünden tema ve Ollama model indirme çıkarıldı.
- Additionals yapısı eklendi: `additionals/ai`, `additionals/profiles`, `additionals/themes`.
- Ollama/Open WebUI core install artık büyük modelleri otomatik indirmez. Model yönetimi `additionals/ai` menüsüne taşındı.
- Google OAuth Manager cached env kullanır: `/root/homelab-secrets/google.env`; sadece eksik değerleri görünür input ile sorar.
- Nextcloud OAuth container adı `hb-nextcloud` veya otomatik detect edilir.
- Jellyfin wizard gate eklendi: Run all core config sırasında wizard eksikse URL gösterir, Enter bekler, scripti otomatik tekrar çalıştırır.
- Chia script path fix: kırılgan `utils/../../utils` source yaklaşımı kaldırıldı.
- ARR root folder pathleri `/media/movies`, `/media/series`, `/media/music` olarak düzeltildi.

## Komut

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bacproxmox/homelabv2.4.4/main/bootstrap.sh)
```
