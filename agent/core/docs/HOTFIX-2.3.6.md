# Homelab v2.4.4 Hotfix

Bu hotfix, v2.3.5 gerçek kurulum testinden çıkan app-level automation sorunlarını düzeltmek için hazırlandı.

## Ana değişiklikler

- Tüm gizli input / `read -s` / `ask_secret` kullanımları kaldırıldı. Girilen değerler terminalde görünür.
- `/root/homelab-secrets` ana secrets klasörü korunur; eski v2.2 script uyumluluğu için `/root/.secrets` symlink desteklenir.
- v2.2'de çalışan app-config mimarisi v2.4 path/naming düzenine refactor edildi.
- ARR auth/config scriptleri geri taşındı:
  - qBittorrent temporary password logdan okunur ve bacmaster şifresiyle değiştirilir.
  - Sonarr/Radarr/Prowlarr/Lidarr auth config.xml üzerinden ayarlanır.
  - qBittorrent download clients, root folders, FlareSolverr proxy ve Prowlarr app sync v2.2 payloadlarıyla çalışır.
- Prowlarr indexer scripti schema-copy yaklaşımına döndü.
- Bazarr language profile ve Recyclarr template scripti geri taşındı.
- Jellyfin config artık API key istemek yerine admin login token ile ilerler.
- Seerr fresh install için eski Jellyseerr DB/settings inject mantığı Seerr path/container yapısına uyarlandı.
- Immich admin signup, ikinci kullanıcı, TrueNAS photo mounts ve external libraries scriptleri geri taşındı.
- Ollama model scripti model varsa skip eder, yoksa indirir.
- Config menu yeniden düzenlendi.

## Önemli not

Bu hotfix, v2.2'de test edilip çalışan payload/mantıkları baz alır. Yeni servis isimleri ve path'ler:

- ARR: `/opt/homelab/arr`
- Seerr: `/opt/homelab/seerr`
- Jellyfin: `/opt/homelab/jellyfin`
- Immich: `/opt/homelab/immich`
- Ollama/OpenWebUI: `/opt/homelab/ollama`
- Lidarr: `/opt/homelab/lidarr`

## Kullanım

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/bacproxmox/homelabv2.4.4/main/bootstrap.sh)
```

Veya mevcut sistemde:

```bash
cd /root
rm -rf /root/homelabv2.4.4
git clone https://github.com/bacproxmox/homelabv2.4.4.git /root/homelabv2.4.4
cd /root/homelabv2.4.4
find . -type f -name "*.sh" -exec dos2unix {} \; 2>/dev/null || true
find . -type f -name "*.sh" -exec chmod +x {} \;
bash menu/install-menu.sh
```
