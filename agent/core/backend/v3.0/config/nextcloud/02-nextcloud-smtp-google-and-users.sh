#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "nextcloud-smtp-google-users"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"
source "$ROOT_DIR/utils/env-write.sh"

load_env_file "$SECRETS_DIR/smtp.env"
load_env_file "$SECRETS_DIR/google.env"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
{
  write_env_header
  write_env_line SMTP_HOST "${SMTP_HOST:-smtppro.zoho.eu}"
  write_env_line SMTP_PORT "${SMTP_PORT:-465}"
  write_env_line SMTP_SECURE "${SMTP_SECURE:-ssl}"
  write_env_line SMTP_FROM_LOCAL "admin"
  write_env_line SMTP_DOMAIN "bacmastercloud.com"
  write_env_line NEXTCLOUD_SMTP_USER "admin@bacmastercloud.com"
  write_env_line NEXTCLOUD_SMTP_PASS "${ZOHO_NEXTCLOUD_APP_PASS:-}"
  write_env_line GOOGLE_CLIENT_ID "${GOOGLE_CLIENT_ID:-}"
  write_env_line GOOGLE_CLIENT_SECRET "${GOOGLE_CLIENT_SECRET:-}"
  write_env_line BACMASTER_USER "${BACMASTER_USER:-bacmaster}"
  write_env_line BACMASTER_PASS "${BACMASTER_PASS:-}"
} > "$TMP/nextcloud-post.env"

cat > "$TMP/nextcloud-post-config.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /opt/homelab/nextcloud || { echo "❌ /opt/homelab/nextcloud yok"; exit 1; }
[[ -f .env ]] && { set -a; source .env; set +a; }
occ(){ docker exec -u www-data hb-nextcloud php occ "$@"; }
occ_status_text(){ occ status 2>&1 || true; }
occ_installed(){ occ_status_text | grep -q 'installed:[[:space:]]*true'; }
wait_ready(){ for _ in $(seq 1 120); do docker exec hb-nextcloud test -f /var/www/html/version.php >/dev/null 2>&1 && return 0; sleep 2; done; return 1; }
ensure_installed(){
  wait_ready || { echo "❌ Nextcloud app code hazır değil"; docker logs hb-nextcloud --tail=80 || true; exit 1; }
  if occ_installed; then echo "✅ Nextcloud installed:true"; return 0; fi
  echo "🧩 Nextcloud installed:false; maintenance:install gate çalışıyor..."
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

ensure_installed

occ config:system:set trusted_domains 0 --value="192.168.50.104"
occ config:system:set trusted_domains 1 --value="cloud.bacmastercloud.com"
occ config:system:set trusted_domains 2 --value="cloud-api.bacmastercloud.com"
occ config:system:set overwrite.cli.url --value="http://192.168.50.104:8080"
occ config:system:delete overwritehost >/dev/null 2>&1 || true
occ config:system:delete overwriteprotocol >/dev/null 2>&1 || true

if [[ -n "${NEXTCLOUD_SMTP_PASS:-}" ]]; then
  occ config:system:set mail_smtpmode --value="smtp"
  occ config:system:set mail_smtphost --value="${SMTP_HOST:-smtppro.zoho.eu}"
  occ config:system:set mail_smtpport --value="${SMTP_PORT:-465}"
  occ config:system:set mail_smtpsecure --value="${SMTP_SECURE:-ssl}"
  occ config:system:set mail_smtpauth --value="1"
  occ config:system:set mail_smtpname --value="${NEXTCLOUD_SMTP_USER:-admin@bacmastercloud.com}"
  occ config:system:set mail_smtppassword --value="${NEXTCLOUD_SMTP_PASS}" >/dev/null
  occ config:system:set mail_from_address --value="${SMTP_FROM_LOCAL:-admin}"
  occ config:system:set mail_domain --value="${SMTP_DOMAIN:-bacmastercloud.com}"
  echo "✅ Nextcloud SMTP ayarlandı (password redacted)"
else
  echo "⚠️ ZOHO_NEXTCLOUD_APP_PASS boş, Nextcloud SMTP atlandı"
fi

if [[ -n "${GOOGLE_CLIENT_ID:-}" && -n "${GOOGLE_CLIENT_SECRET:-}" ]]; then
  occ app:install sociallogin || true
  occ app:enable sociallogin || true
  echo "ℹ️ Google OAuth env mevcut. sociallogin app kuruldu/aktif edildi; provider UI/API doğrulaması gerekebilir."
fi

create_user(){
  local u="$1" p="$2"
  [[ -n "$u" && -n "$p" ]] || return 0
  if occ user:info "$u" >/dev/null 2>&1; then
    echo "✅ Nextcloud user zaten var: $u"
  else
    OC_PASS="$p" occ user:add --password-from-env "$u"
    echo "✅ Nextcloud user oluşturuldu: $u"
  fi
}
create_user "${BACMASTER_USER:-bacmaster}" "${BACMASTER_PASS:-}"
occ maintenance:repair || true
REMOTE
chmod +x "$TMP/nextcloud-post-config.sh"
rscp "$TMP/nextcloud-post-config.sh" 104 /tmp/hv2313-nextcloud-post-config.sh
rscp "$TMP/nextcloud-post.env" 104 /tmp/hv2313-nextcloud-post.env
rssh 104 "sudo bash -c 'set -a; source /tmp/hv2313-nextcloud-post.env; set +a; bash /tmp/hv2313-nextcloud-post-config.sh; rm -f /tmp/hv2313-nextcloud-post.env'"
