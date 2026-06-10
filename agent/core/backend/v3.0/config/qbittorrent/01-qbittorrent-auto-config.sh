#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "qbittorrent-auto-config"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env

QBIT_URL="${QBIT_URL:-http://192.168.50.102:8080}"
QBIT_USER="${ARR_USER:-${BACMASTER_USER:-bacmaster}}"
QBIT_PASS="${ARR_PASS:-${BACMASTER_PASS:-}}"
SMTP_FROM="${SMTP_FROM:-admin@bacmastercloud.com}"
SMTP_USER="${QBIT_SMTP_USER:-${SMTP_FROM}}"
SMTP_PASS="${QBIT_SMTP_PASS:-${ZOHO_SEERR_APP_PASS:-${ZOHO_NEXTCLOUD_APP_PASS:-}}}"
SMTP_HOST="${SMTP_HOST:-smtppro.zoho.eu}"
SMTP_PORT="${SMTP_PORT:-465}"
SMTP_TEST_TO="${SMTP_TEST_TO:-$SMTP_FROM}"
COOKIE_FILE="/tmp/qbittorrent-v247.cookies"

[[ -n "$QBIT_PASS" ]] || { echo "⚠️ qBittorrent şifresi yok; BACMASTER_PASS/ARR_PASS bekleniyor."; exit 0; }

wait_qbit(){
  echo "⏳ qBittorrent API bekleniyor: $QBIT_URL"
  for _ in {1..60}; do
    curl -fsS "$QBIT_URL/api/v2/app/version" >/dev/null 2>&1 && return 0
    curl -fsS "$QBIT_URL" >/dev/null 2>&1 && return 0
    sleep 2
  done
  echo "⚠️ qBittorrent WebUI/API erişilemedi; config atlandı."
  exit 0
}

qb_login(){
  rm -f "$COOKIE_FILE"
  curl -fsS -i -c "$COOKIE_FILE" \
    --data-urlencode "username=$1" \
    --data-urlencode "password=$2" \
    "$QBIT_URL/api/v2/auth/login" | grep -qi Ok
}

set_prefs(){
  local json="$1"
  curl -fsS -b "$COOKIE_FILE" --data-urlencode "json=$json" "$QBIT_URL/api/v2/app/setPreferences" >/dev/null
}

create_category(){
  local cat="$1" path="$2"
  curl -fsS -b "$COOKIE_FILE" \
    --data-urlencode "category=$cat" \
    --data-urlencode "savePath=$path" \
    "$QBIT_URL/api/v2/torrents/createCategory" >/dev/null 2>&1 || true
}

wait_qbit
if ! qb_login "$QBIT_USER" "$QBIT_PASS"; then
  echo "⚠️ qBittorrent login başarısız: $QBIT_USER. Önce config/arr/05-configure-service-auth.sh çalışmış olmalı."
  exit 0
fi

echo "🧲 qBittorrent policy uygulanıyor..."
base_json='{
  "save_path":"/downloads/",
  "temp_path_enabled":false,
  "create_subfolder_enabled":true,
  "queueing_enabled":true,
  "max_active_downloads":30,
  "max_active_uploads":0,
  "max_active_torrents":30,
  "up_limit":1024000,
  "max_ratio_enabled":true,
  "max_ratio":0,
  "max_seeding_time_enabled":true,
  "max_seeding_time":0,
  "max_ratio_act":0,
  "add_trackers_enabled":false
}'
set_prefs "$base_json"

for pair in \
  "sonarr|/downloads/sonarr" \
  "radarr|/downloads/radarr" \
  "lidarr|/downloads/lidarr"; do
  IFS='|' read -r c p <<<"$pair"
  create_category "$c" "$p"
done

if [[ -n "$SMTP_PASS" ]]; then
  echo "📧 qBittorrent SMTP notification ayarlanıyor: $SMTP_USER@$SMTP_HOST:$SMTP_PORT (password redacted)"
  smtp_json="$(jq -n \
    --arg sender "$SMTP_FROM" \
    --arg email "$SMTP_TEST_TO" \
    --arg smtp "${SMTP_HOST}:${SMTP_PORT}" \
    --arg user "$SMTP_USER" \
    --arg pass "$SMTP_PASS" \
    '{
      mail_notification_enabled:true,
      mail_notification_sender:$sender,
      mail_notification_email:$email,
      mail_notification_smtp_server:$smtp,
      mail_notification_smtp:$smtp,
      mail_notification_ssl_enabled:true,
      mail_notification_req_auth:true,
      mail_notification_auth_enabled:true,
      mail_notification_username:$user,
      mail_notification_password:$pass
    }')"
  set_prefs "$smtp_json" || echo "⚠️ qBittorrent SMTP preference update başarısız; qBittorrent sürümünde bazı key isimleri farklı olabilir."
else
  echo "⚠️ SMTP app password bulunamadı; qBittorrent mail notification atlandı."
fi

curl -fsS -b "$COOKIE_FILE" "$QBIT_URL/api/v2/app/preferences" \
  | jq '{max_active_downloads,max_active_uploads,max_active_torrents,up_limit,max_ratio_enabled,max_ratio,max_seeding_time_enabled,max_seeding_time,max_ratio_act,mail_notification_enabled}' \
  2>/dev/null || true

echo "✅ qBittorrent v2.4.7 policy tamamlandı."
