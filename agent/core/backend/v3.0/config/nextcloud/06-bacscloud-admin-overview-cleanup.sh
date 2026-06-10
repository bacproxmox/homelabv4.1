#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "bacscloud-admin-overview-cleanup"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"

TMP="$(mktemp -d)"
cat > "$TMP/cleanup.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
NC_CONTAINER="${NC_CONTAINER:-hb-nextcloud}"
PUBLIC_HOST="${PUBLIC_HOST:-cloud.bacmastercloud.com}"
PUBLIC_API_HOST="${PUBLIC_API_HOST:-cloud-api.bacmastercloud.com}"
LAN_HOST="${LAN_HOST:-192.168.50.104:8080}"
CLOUDFLARED_PROXY_IP="${CLOUDFLARED_PROXY_IP:-192.168.50.103}"

dkr(){ docker "$@"; }
occ(){ dkr exec -u www-data "$NC_CONTAINER" php occ "$@"; }
rootsh(){ dkr exec -u root "$NC_CONTAINER" sh -lc "$*"; }

dkr ps --format '{{.Names}}' | grep -qx "$NC_CONTAINER" || { echo "❌ $NC_CONTAINER çalışmıyor"; dkr ps; exit 1; }
occ status | grep -q 'installed: true' || { echo "❌ Nextcloud installed=true değil"; occ status || true; exit 1; }

echo "🌐 Trusted domains / proxy / HSTS ayarları..."
occ config:system:set trusted_domains 0 --value="$PUBLIC_HOST" >/dev/null
occ config:system:set trusted_domains 1 --value="$PUBLIC_API_HOST" >/dev/null
occ config:system:set trusted_domains 2 --value="$LAN_HOST" >/dev/null
occ config:system:set trusted_domains 3 --value="192.168.50.104" >/dev/null
occ config:system:set overwrite.cli.url --value="https://${PUBLIC_HOST}" >/dev/null
occ config:system:set overwritehost --value="$PUBLIC_HOST" >/dev/null
occ config:system:set overwriteprotocol --value="https" >/dev/null
occ config:system:set overwritecondaddr --value="^${CLOUDFLARED_PROXY_IP//./\\.}$" >/dev/null || true
occ config:system:set trusted_proxies 0 --value="$CLOUDFLARED_PROXY_IP" >/dev/null || true
occ config:system:set forwarded_for_headers 0 --value="HTTP_X_FORWARDED_FOR" >/dev/null || true
occ config:system:set forwarded_for_headers 1 --value="HTTP_CF_CONNECTING_IP" >/dev/null || true

rootsh "a2enmod headers rewrite remoteip >/dev/null 2>&1 || true
cat >/etc/apache2/conf-available/homelab-bacscloud-hardening.conf <<'APACHE'
SetEnvIf X-Forwarded-Proto \"https\" HTTPS=on
RemoteIPHeader X-Forwarded-For
Header always set Strict-Transport-Security \"max-age=15552000; includeSubDomains\"
Header always set Referrer-Policy \"no-referrer\"
Header always set X-Content-Type-Options \"nosniff\"
Header always set X-Frame-Options \"SAMEORIGIN\"
APACHE
a2enconf homelab-bacscloud-hardening >/dev/null 2>&1 || true
apache2ctl -t"

echo "🧩 appdata/theming repair..."
DATA_DIR="$(occ config:system:get datadirectory)"
INSTANCE_ID="$(occ config:system:get instanceid)"
APPDATA_DIR="${DATA_DIR}/appdata_${INSTANCE_ID}"
rootsh "mkdir -p '${APPDATA_DIR}/theming/global' '${APPDATA_DIR}/theming/images' '${APPDATA_DIR}/css' '${APPDATA_DIR}/js' '${APPDATA_DIR}/preview' /etc/cron.d && touch '${DATA_DIR}/.ocdata' && chown -R www-data:www-data '${APPDATA_DIR}' '${DATA_DIR}/.ocdata'"
occ files:scan-app-data || true
occ maintenance:repair || true

echo "🎨 Bacscloud branding / AppAPI cleanup / cron..."
occ config:app:set theming name --value="Bacscloud" >/dev/null || true
occ config:app:set theming slogan --value="Kişisel bulutun" >/dev/null || true
occ config:app:set theming url --value="https://${PUBLIC_HOST}" >/dev/null || true
occ background:cron || true
rootsh "mkdir -p /etc/cron.d && cat >/etc/cron.d/homelab-nextcloud <<'CRON'
*/5 * * * * root docker exec -u www-data hb-nextcloud php -f /var/www/html/cron.php >/dev/null 2>&1
CRON
chmod 644 /etc/cron.d/homelab-nextcloud"
if occ app:list | grep -qE '^  - app_api:'; then occ app:disable app_api || true; fi

dkr restart "$NC_CONTAINER" >/dev/null
sleep 15
curl -k -sSI "https://${PUBLIC_HOST}/status.php" | grep -iE 'HTTP/|strict-transport-security|server' || true
occ status
REMOTE
chmod +x "$TMP/cleanup.sh"
rscp "$TMP/cleanup.sh" 104 /tmp/bacscloud-admin-overview-cleanup.sh
rssh 104 "sudo bash /tmp/bacscloud-admin-overview-cleanup.sh"
rm -rf "$TMP"
