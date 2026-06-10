#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../utils/env-loader.sh"
source "$SCRIPT_DIR/../../utils/logging.sh"
start_log "uptime-kuma-smtp-note"
load_all_env
cat <<NOTE
ℹ️ Uptime Kuma SMTP otomasyonu notu

Uptime Kuma notification ayarları için public/stable bir local CLI yok.
Bu yüzden v2.3 şimdilik güvenli not üretir, SMTP testini otomatik yapar.

Uptime Kuma UI:
  http://192.168.50.103:3001

SMTP:
  Host: ${SMTP_HOST:-smtppro.zoho.eu}
  Port: ${SMTP_PORT:-465}
  Security: SSL/TLS
  From: ${SMTP_FROM:-admin@bacmastercloud.com}
  Username: ${SMTP_FROM:-admin@bacmastercloud.com}
  Password var: ZOHO_UPTIME_KUMA_APP_PASS
  Test To: ${SMTP_TEST_TO:-admin@bacmastercloud.com}

Test:
  bash maintenance/alerts/test-smtp-send.sh uptime-kuma
NOTE
