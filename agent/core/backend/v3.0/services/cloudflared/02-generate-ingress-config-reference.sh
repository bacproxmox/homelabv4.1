#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT_DIR/services/cloudflared/generated-ingress-reference.yml"
cat > "$OUT" <<'EOF'
# Reference only. If you use token-based named tunnels from Cloudflare dashboard,
# routes are usually managed in Zero Trust UI. This file is kept as canonical mapping.
ingress:
  - hostname: pve.bacmastercloud.com
    service: https://192.168.50.100:8006
    originRequest: { noTLSVerify: true }
  - hostname: pve-api.bacmastercloud.com
    service: https://192.168.50.100:8006
    originRequest: { noTLSVerify: true }
  - hostname: truenas.bacmastercloud.com
    service: http://192.168.50.101
  - hostname: truenas-api.bacmastercloud.com
    service: http://192.168.50.101
  - hostname: qbittorrent.bacmastercloud.com
    service: http://192.168.50.102:8080
  - hostname: qbittorrent-api.bacmastercloud.com
    service: http://192.168.50.102:8080
  - hostname: sonarr.bacmastercloud.com
    service: http://192.168.50.102:8989
  - hostname: sonarr-api.bacmastercloud.com
    service: http://192.168.50.102:8989
  - hostname: radarr.bacmastercloud.com
    service: http://192.168.50.102:7878
  - hostname: radarr-api.bacmastercloud.com
    service: http://192.168.50.102:7878
  - hostname: prowlarr.bacmastercloud.com
    service: http://192.168.50.102:9696
  - hostname: prowlarr-api.bacmastercloud.com
    service: http://192.168.50.102:9696
  - hostname: bazarr.bacmastercloud.com
    service: http://192.168.50.102:6767
  - hostname: bazarr-api.bacmastercloud.com
    service: http://192.168.50.102:6767
  - hostname: bacneyplus.bacmastercloud.com
    service: http://192.168.50.102:5055
  - hostname: bacneyplus-api.bacmastercloud.com
    service: http://192.168.50.102:5055
  - hostname: status.bacmastercloud.com
    service: http://192.168.50.103:3001
  - hostname: status-api.bacmastercloud.com
    service: http://192.168.50.103:3001
  - hostname: cloud.bacmastercloud.com
    service: http://192.168.50.104:8080
  - hostname: cloud-api.bacmastercloud.com
    service: http://192.168.50.104:8080
  - hostname: home.bacmastercloud.com
    service: http://192.168.50.105:8123
  - hostname: home-api.bacmastercloud.com
    service: http://192.168.50.105:8123
  - hostname: bacsflix.bacmastercloud.com
    service: http://192.168.50.106:8096
  - hostname: bacsflix-api.bacmastercloud.com
    service: http://192.168.50.106:8096
  - hostname: photos.bacmastercloud.com
    service: http://192.168.50.106:2283
  - hostname: photos-api.bacmastercloud.com
    service: http://192.168.50.106:2283
  - hostname: ai.bacmastercloud.com
    service: http://192.168.50.106:3000
  - hostname: ai-api.bacmastercloud.com
    service: http://192.168.50.106:3000
  - hostname: music.bacmastercloud.com
    service: http://192.168.50.106:8686
  - hostname: music-api.bacmastercloud.com
    service: http://192.168.50.106:8686
  - hostname: pbs.bacmastercloud.com
    service: https://192.168.50.110:8007
    originRequest: { noTLSVerify: true }
  - hostname: pbs-api.bacmastercloud.com
    service: https://192.168.50.110:8007
    originRequest: { noTLSVerify: true }
  - service: http_status:404
EOF
echo "✅ Yazıldı: $OUT"
