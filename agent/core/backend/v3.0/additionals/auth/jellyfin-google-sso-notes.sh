#!/usr/bin/env bash
set -Eeuo pipefail
cat <<'MSG'
🎬 Jellyfin / Bacsflix Google login notu

Jellyfin'de Google login doğrudan core özellik değil. En güvenli iki yol:

1) Cloudflare Access ile Google login
   - bacsflix.bacmastercloud.com erişimini Google hesabıyla korur.
   - Jellyfin'in kendi local login'i yine içeride kalır.
   - Stabil ve reverse-proxy seviyesinde güvenli.

2) Jellyfin SSO/OIDC plugin
   - Google OIDC veya harici IdP ile gerçek uygulama içi SSO sağlayabilir.
   - Plugin uyumluluğu Jellyfin sürümüne bağlı olduğu için v2.4'de deneysel tutulur.

Bu script şimdilik bilinçli olarak konfigürasyon yapmaz; kırılgan SSO ayarı core kuruluma eklenmeyecek.
MSG
