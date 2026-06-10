#!/usr/bin/env bash
set -Eeuo pipefail
cat <<'MSG'
🎟️ Seerr / Bacneyplus Google login notu

Seerr tarafında OIDC/SSO desteği sürüme göre değişebildiği için v2.4'de core kuruluma otomatik bağlanmaz.

Önerilen güvenli yol:
  1) Cloudflare Access ile bacneyplus.bacmastercloud.com'u Google login arkasına almak
  2) Seerr içinde Jellyfin/local auth'u korumak
  3) Native OIDC stabil doğrulanınca additionals/auth altında gerçek otomasyon eklemek
MSG
