#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "bacscloud-production-hardening"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"
source "$ROOT_DIR/utils/env-write.sh"

load_env_file "$SECRETS_DIR/smtp.env"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
{
  write_env_header
  write_env_line NC_DOMAIN "cloud.bacmastercloud.com"
  write_env_line NC_API_DOMAIN "cloud-api.bacmastercloud.com"
  write_env_line ADMIN_EMAIL "${SMTP_FROM:-admin@bacmastercloud.com}"
  write_env_line ADMIN_DISPLAY_NAME "Bacmaster"
  write_env_line SMTP_HOST "${SMTP_HOST:-smtppro.zoho.eu}"
  write_env_line SMTP_PORT "${SMTP_PORT:-465}"
  write_env_line SMTP_SECURE "${SMTP_SECURE:-ssl}"
  write_env_line SMTP_FROM "${SMTP_FROM:-admin@bacmastercloud.com}"
  write_env_line NEXTCLOUD_SMTP_USER "${NEXTCLOUD_SMTP_USER:-${SMTP_FROM:-admin@bacmastercloud.com}}"
  write_env_line NEXTCLOUD_SMTP_PASS "${ZOHO_NEXTCLOUD_APP_PASS:-${NEXTCLOUD_SMTP_PASS:-}}"
} > "$TMP/bacscloud-hardening.env"

cat > "$TMP/apply-bacscloud-hardening.sh" <<'REMOTE'
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
  if occ_installed; then echo "✅ Bacscloud installed:true"; return 0; fi
  echo "🧩 Bacscloud installed:false; maintenance:install gate çalışıyor..."
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
  occ_installed || { echo "❌ Bacscloud install gate başarısız"; occ_status_text; exit 1; }
}

ensure_installed

ADMIN_USER="${NEXTCLOUD_ADMIN_USER:-bacmaster}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@bacmastercloud.com}"
ADMIN_DISPLAY_NAME="${ADMIN_DISPLAY_NAME:-Bacmaster}"
SMTP_FROM="${SMTP_FROM:-admin@bacmastercloud.com}"
SMTP_FROM_LOCAL="${SMTP_FROM%@*}"
SMTP_DOMAIN="${SMTP_FROM#*@}"
SMTP_HOST="${SMTP_HOST:-smtppro.zoho.eu}"
SMTP_PORT="${SMTP_PORT:-465}"
SMTP_SECURE="${SMTP_SECURE:-ssl}"
NEXTCLOUD_SMTP_USER="${NEXTCLOUD_SMTP_USER:-$SMTP_FROM}"

# Normalize user-facing branding.
echo "🎨 Bacscloud branding uygulanıyor..."
occ app:enable theming >/dev/null 2>&1 || true
occ config:app:set theming name --value="Bacscloud" >/dev/null 2>&1 || true
occ config:app:set theming slogan --value="Bacmaster Cloud" >/dev/null 2>&1 || true
occ config:app:set theming url --value="https://${NC_DOMAIN:-cloud.bacmastercloud.com}" >/dev/null 2>&1 || true
occ config:app:set theming color --value="#0f172a" >/dev/null 2>&1 || true

# Admin profile email is required for reliable test mails and password notifications.
echo "👤 Admin profil ayarları..."
occ user:setting "$ADMIN_USER" settings email "$ADMIN_EMAIL" || true
occ user:setting "$ADMIN_USER" settings display_name "$ADMIN_DISPLAY_NAME" || true
occ user:setting "$ADMIN_USER" settings locale "tr" || true
occ user:setting "$ADMIN_USER" settings lang "tr" || true

# Cloudflare / trusted domain posture. Keep direct LAN access possible but make CLI/domain canonical HTTPS.
echo "🌐 Trusted domain / reverse proxy ayarları..."
occ config:system:set trusted_domains 0 --value="192.168.50.104"
occ config:system:set trusted_domains 1 --value="${NC_DOMAIN:-cloud.bacmastercloud.com}"
occ config:system:set trusted_domains 2 --value="${NC_API_DOMAIN:-cloud-api.bacmastercloud.com}"
occ config:system:set overwrite.cli.url --value="https://${NC_DOMAIN:-cloud.bacmastercloud.com}"
occ config:system:set overwriteprotocol --value="https"
# Keep Cloudflare canonical HTTPS behavior, but do not force direct LAN clients to behave as HTTPS.
# cloudflared runs on VM103 and reaches VM104 from 192.168.50.103.
occ config:system:set trusted_proxies 0 --value="192.168.50.103" || true
occ config:system:set trusted_proxies 1 --value="172.16.0.0/12" || true
occ config:system:set trusted_proxies 2 --value="10.0.0.0/8" || true
occ config:system:set overwritecondaddr --value='^192\.168\.50\.103$|^172\.|^10\.' || true
occ config:system:set forwarded_for_headers 0 --value="HTTP_CF_CONNECTING_IP" || true
occ config:system:set forwarded_for_headers 1 --value="HTTP_X_FORWARDED_FOR" || true

# SMTP reference: Zoho EU Pro / port 465 / SSL/TLS from confirmed UI screenshot.
if [[ -n "${NEXTCLOUD_SMTP_PASS:-}" ]]; then
  echo "📧 Bacscloud SMTP uygulanıyor: ${NEXTCLOUD_SMTP_USER}@${SMTP_HOST}:${SMTP_PORT} (${SMTP_SECURE}, password redacted)"
  occ config:system:set mail_smtpmode --value="smtp"
  occ config:system:set mail_smtphost --value="$SMTP_HOST"
  occ config:system:set mail_smtpport --value="$SMTP_PORT"
  occ config:system:set mail_smtpsecure --value="$SMTP_SECURE"
  occ config:system:set mail_smtpauth --value="1"
  occ config:system:set mail_smtpname --value="$NEXTCLOUD_SMTP_USER"
  occ config:system:set mail_smtppassword --value="$NEXTCLOUD_SMTP_PASS" >/dev/null
  occ config:system:set mail_from_address --value="$SMTP_FROM_LOCAL"
  occ config:system:set mail_domain --value="$SMTP_DOMAIN"
else
  echo "⚠️ ZOHO_NEXTCLOUD_APP_PASS/NEXTCLOUD_SMTP_PASS boş; SMTP password yazılmadı. Diğer SMTP ayarları korunuyor."
fi

# Admin warnings cleanup.
echo "🧰 Cron / maintenance / locale / DB repair ayarları..."
occ background:cron || true
mkdir -p /etc/cron.d
cat >/etc/cron.d/homelab-nextcloud <<'CRON'
*/5 * * * * root docker exec -u www-data hb-nextcloud php -f /var/www/html/cron.php >/dev/null 2>&1
CRON
chmod 644 /etc/cron.d/homelab-nextcloud
occ config:system:set default_phone_region --value="TR" || true
occ config:system:set default_locale --value="tr_TR" || true
occ config:system:set default_language --value="tr" || true
occ config:system:set logtimezone --value="Europe/Istanbul" || true
occ config:system:set maintenance_window_start --type=integer --value=1 || true
occ config:system:set memcache.local --value="\\OC\\Memcache\\APCu" || true
occ config:system:set memcache.locking --value="\\OC\\Memcache\\Redis" || true
occ config:system:set redis host --value="redis" || true
occ config:system:set redis port --type=integer --value=6379 || true

occ maintenance:repair --include-expensive || true
occ db:add-missing-indices || true
occ db:add-missing-columns || true
occ db:add-missing-primary-keys || true
occ maintenance:mimetype:update-db --repair-filecache || true
# Do NOT run `maintenance:mimetype:update-js` automatically. In current Nextcloud builds
# it can regenerate core/js/mimetypelist.js and trigger INVALID_HASH integrity warnings.
occ files:scan --all || true

# Add HSTS header for public Cloudflare HTTPS responses. Local direct access remains HTTP on :8080.
if command -v a2enmod >/dev/null 2>&1; then
  a2enmod headers >/dev/null 2>&1 || true
  cat >/etc/apache2/conf-available/homelab-hsts.conf <<'APACHE'
<IfModule mod_headers.c>
    Header always set Strict-Transport-Security "max-age=15552000; includeSubDomains"
</IfModule>
APACHE
  a2enconf homelab-hsts >/dev/null 2>&1 || true
  apache2ctl graceful >/dev/null 2>&1 || true
fi

# Do not print secrets.
echo "✅ Bacscloud hardening tamamlandı. Mail password/API secret loga basılmadı."
echo "📋 Kısa doğrulama:"
for key in mail_smtpmode mail_smtphost mail_smtpport mail_smtpsecure mail_smtpauth mail_smtpname mail_from_address mail_domain default_phone_region maintenance_window_start overwrite.cli.url overwriteprotocol overwritecondaddr; do
  printf '  %-26s ' "$key"
  occ config:system:get "$key" || true
done
REMOTE
chmod +x "$TMP/apply-bacscloud-hardening.sh"

rscp "$TMP/bacscloud-hardening.env" 104 /tmp/bacscloud-hardening.env
rscp "$TMP/apply-bacscloud-hardening.sh" 104 /tmp/apply-bacscloud-hardening.sh
rssh 104 "sudo bash -c 'set -a; source /tmp/bacscloud-hardening.env; set +a; bash /tmp/apply-bacscloud-hardening.sh; rm -f /tmp/bacscloud-hardening.env /tmp/apply-bacscloud-hardening.sh'"
