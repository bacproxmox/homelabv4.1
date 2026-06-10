#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "nextcloud-smtp-config"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"
source "$ROOT_DIR/utils/env-write.sh"

load_env_file "$SECRETS_DIR/smtp.env"
load_env_file "$SECRETS_DIR/smtp-service-reference.env"

SMTP_HOST="${SMTP_HOST:-smtppro.zoho.eu}"
SMTP_PORT="${SMTP_PORT:-465}"
SMTP_SECURE="${SMTP_SECURE:-ssl}"
SMTP_FROM="${SMTP_FROM:-admin@bacmastercloud.com}"
SMTP_FROM_LOCAL="${SMTP_FROM%@*}"
SMTP_DOMAIN="${SMTP_FROM#*@}"
NEXTCLOUD_SMTP_USER="${NEXTCLOUD_SMTP_USER:-$SMTP_FROM}"
NEXTCLOUD_SMTP_PASS="${ZOHO_NEXTCLOUD_APP_PASS:-${NEXTCLOUD_SMTP_PASS:-}}"

if [[ -z "$NEXTCLOUD_SMTP_PASS" ]]; then
  echo "❌ Nextcloud SMTP app password bulunamadı. Beklenen env: ZOHO_NEXTCLOUD_APP_PASS veya NEXTCLOUD_SMTP_PASS"
  exit 1
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
{
  write_env_header
  write_env_line SMTP_HOST "$SMTP_HOST"
  write_env_line SMTP_PORT "$SMTP_PORT"
  write_env_line SMTP_SECURE "$SMTP_SECURE"
  write_env_line SMTP_FROM_LOCAL "$SMTP_FROM_LOCAL"
  write_env_line SMTP_DOMAIN "$SMTP_DOMAIN"
  write_env_line NEXTCLOUD_SMTP_USER "$NEXTCLOUD_SMTP_USER"
  write_env_line NEXTCLOUD_SMTP_PASS "$NEXTCLOUD_SMTP_PASS"
} > "$TMP/nextcloud-smtp.env"

cat > "$TMP/apply-nextcloud-smtp.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /opt/homelab/nextcloud || { echo "❌ /opt/homelab/nextcloud yok"; exit 1; }
[[ -f .env ]] && { set -a; source .env; set +a; }
occ(){ docker exec -u www-data hb-nextcloud php occ "$@"; }
occ_status_text(){ occ status 2>&1 || true; }
occ_installed(){ occ_status_text | grep -q 'installed:[[:space:]]*true'; }
ensure_installed(){
  for _ in $(seq 1 120); do docker exec hb-nextcloud test -f /var/www/html/version.php >/dev/null 2>&1 && break; sleep 2; done
  if occ_installed; then return 0; fi
  echo "🧩 Nextcloud installed:false; SMTP öncesi maintenance:install gate çalışıyor..."
  : "${MYSQL_DATABASE:?MYSQL_DATABASE yok}"; : "${MYSQL_USER:?MYSQL_USER yok}"; : "${MYSQL_PASSWORD:?MYSQL_PASSWORD yok}"; : "${NEXTCLOUD_ADMIN_USER:?NEXTCLOUD_ADMIN_USER yok}"; : "${NEXTCLOUD_ADMIN_PASSWORD:?NEXTCLOUD_ADMIN_PASSWORD yok}"
  admin_dir="/mnt/nextcloud/data/${NEXTCLOUD_ADMIN_USER}"
  if [[ -e "$admin_dir" ]]; then
    backup="/mnt/nextcloud/data/${NEXTCLOUD_ADMIN_USER}.preinstall-backup-$(date +%Y%m%d-%H%M%S)"
    echo "⚠️ Admin data dir yedeğe taşınıyor: $backup"
    mv "$admin_dir" "$backup"
  fi
  chown -R 33:33 /mnt/nextcloud/data
  chmod 750 /mnt/nextcloud/data
  occ maintenance:install --database mysql --database-name "$MYSQL_DATABASE" --database-user "$MYSQL_USER" --database-pass "$MYSQL_PASSWORD" --database-host db --admin-user "$NEXTCLOUD_ADMIN_USER" --admin-pass "$NEXTCLOUD_ADMIN_PASSWORD"
  occ_installed || { echo "❌ Nextcloud install gate başarısız"; occ_status_text; exit 1; }
}

if ! docker ps --format '{{.Names}}' | grep -qx 'hb-nextcloud'; then
  echo "❌ hb-nextcloud çalışmıyor."
  docker ps -a | grep -i nextcloud || true
  exit 1
fi

ensure_installed

occ config:system:set mail_smtpmode --value="smtp"
occ config:system:set mail_smtphost --value="$SMTP_HOST"
occ config:system:set mail_smtpport --value="$SMTP_PORT"
occ config:system:set mail_smtpsecure --value="$SMTP_SECURE"
occ config:system:set mail_smtpauth --value="1"
occ config:system:set mail_smtpname --value="$NEXTCLOUD_SMTP_USER"
occ config:system:set mail_smtppassword --value="$NEXTCLOUD_SMTP_PASS" >/dev/null
occ config:system:set mail_from_address --value="$SMTP_FROM_LOCAL"
occ config:system:set mail_domain --value="$SMTP_DOMAIN"

echo "✅ Nextcloud SMTP ayarlandı: ${NEXTCLOUD_SMTP_USER}@${SMTP_HOST}:${SMTP_PORT} (password redacted)"
echo "📋 Aktif mail ayarları:"
for key in mail_smtpmode mail_smtphost mail_smtpport mail_smtpsecure mail_smtpauth mail_smtpname mail_from_address mail_domain; do
  printf '  %-20s ' "$key"
  occ config:system:get "$key" || true
done
REMOTE
chmod +x "$TMP/apply-nextcloud-smtp.sh"
rscp "$TMP/nextcloud-smtp.env" 104 /tmp/nextcloud-smtp.env
rscp "$TMP/apply-nextcloud-smtp.sh" 104 /tmp/apply-nextcloud-smtp.sh
rssh 104 "sudo bash -c 'set -a; source /tmp/nextcloud-smtp.env; set +a; bash /tmp/apply-nextcloud-smtp.sh; rm -f /tmp/nextcloud-smtp.env /tmp/apply-nextcloud-smtp.sh'"
