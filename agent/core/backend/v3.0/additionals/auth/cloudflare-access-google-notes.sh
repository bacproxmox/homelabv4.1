#!/usr/bin/env bash
set -Eeuo pipefail
cat <<'MSG'
🌩️ Cloudflare Access Google login notu

Google login'i servislerin önüne koymak için en stabil yol Cloudflare Access policy kullanmak:

Örnek hedefler:
  - bacsflix.bacmastercloud.com
  - bacneyplus.bacmastercloud.com
  - ai.bacmastercloud.com
  - cloud.bacmastercloud.com

Bu ayar Cloudflare Zero Trust dashboard tarafında yapılır. v2.4 scriptleri tunnel/route üretir, Access policy'leri ise güvenli şekilde dashboard veya ileride API token ile yönetilebilir.
MSG
