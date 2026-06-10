#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "arr-export-api-keys"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"
source "$ROOT_DIR/utils/env-write.sh"

OUT="$SECRETS_DIR/arr-api.env"
TMP="$(mktemp)"
{
  write_env_header
  echo "# Exported from app config.xml files. Re-run after fresh container reset."
} > "$TMP"

grab() {
  local var="$1" vm="$2" path="$3"
  local val=""
  val="$(rssh "$vm" "sudo sed -n 's:.*<ApiKey>\\(.*\\)</ApiKey>.*:\\1:p' '$path' 2>/dev/null | head -n1" || true)"
  if [[ -n "$val" ]]; then
    write_env_line "$var" "$val" >> "$TMP"
    echo "✅ $var bulundu"
  else
    echo "⚠️  $var bulunamadı: $path"
  fi
}

grab SONARR_API_KEY 102 /opt/homelab/arr/config/sonarr/config.xml
grab RADARR_API_KEY 102 /opt/homelab/arr/config/radarr/config.xml
grab PROWLARR_API_KEY 102 /opt/homelab/arr/config/prowlarr/config.xml
grab BAZARR_API_KEY 102 /opt/homelab/arr/config/bazarr/config/config.yaml
grab LIDARR_API_KEY 106 /opt/homelab/lidarr/config/lidarr/config.xml

install -m 600 "$TMP" "$OUT"
rm -f "$TMP"
echo "✅ API key env yazıldı: $OUT"
