#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../utils/env-loader.sh"
source "$SCRIPT_DIR/../../utils/logging.sh"
start_log "write-service-smtp-reference"
load_all_env

OUT="$SECRETS_DIR/smtp-service-reference.env"
cat > "$OUT" <<REF
# Homelab v2.3 SMTP service reference
# Bu dosya bilgi amaçlıdır. Asıl app password değerleri smtp.env içindedir.
SMTP_HOST=${SMTP_HOST:-smtppro.zoho.eu}
SMTP_PORT=${SMTP_PORT:-465}
SMTP_SECURITY=${SMTP_SECURITY:-SSL/TLS}
SMTP_SECURE=${SMTP_SECURE:-ssl}
SMTP_FROM=${SMTP_FROM:-admin@bacmastercloud.com}
SMTP_TEST_TO=${SMTP_TEST_TO:-admin@bacmastercloud.com}

NEXTCLOUD_PASS_VAR=ZOHO_NEXTCLOUD_APP_PASS
IMMICH_PASS_VAR=ZOHO_IMMICH_APP_PASS
JELLYSEERR_PASS_VAR=ZOHO_JELLYSEERR_APP_PASS
UPTIME_KUMA_PASS_VAR=ZOHO_UPTIME_KUMA_APP_PASS
TRUENAS_PASS_VAR=ZOHO_TRUENAS_APP_PASS
REF
chmod 600 "$OUT"
echo "✅ SMTP referans dosyası yazıldı: $OUT"
echo "Test için: bash maintenance/alerts/test-smtp-send.sh nextcloud"
