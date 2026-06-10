#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "nextcloud-local-cloudflare-fix"
source "$ROOT_DIR/utils/remote.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/nextcloud-install-gate-and-local-fix.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /opt/homelab/nextcloud || { echo "❌ /opt/homelab/nextcloud yok"; exit 1; }
[[ -f .env ]] && { set -a; source .env; set +a; }

show_nc_logs(){ docker ps -a --filter name=hb-nextcloud || true; docker logs hb-nextcloud --tail=120 || true; }
wait_nextcloud_ready(){
  echo "⏳ Nextcloud readiness kontrolü..."
  for i in $(seq 1 120); do
    state="$(docker inspect -f '{{.State.Status}} {{.State.Restarting}}' hb-nextcloud 2>/dev/null || true)"
    if echo "$state" | grep -q '^running false' && docker exec hb-nextcloud test -f /var/www/html/version.php >/dev/null 2>&1; then
      echo "✅ hb-nextcloud running ve version.php mevcut."
      return 0
    fi
    sleep 3
  done
  echo "❌ Nextcloud hazır değil veya /var/www/html/version.php eksik."
  show_nc_logs
  return 1
}
occ(){ docker exec -u www-data hb-nextcloud php occ "$@"; }
occ_status_text(){ occ status 2>&1 || true; }
occ_installed(){ occ_status_text | grep -q 'installed:[[:space:]]*true'; }
ensure_installed(){
  wait_nextcloud_ready
  if occ_installed; then
    echo "✅ Nextcloud already installed."
    return 0
  fi
  echo "🧩 Nextcloud installed:false; maintenance:install gate çalışıyor..."
  : "${MYSQL_DATABASE:?MYSQL_DATABASE .env içinde yok}"
  : "${MYSQL_USER:?MYSQL_USER .env içinde yok}"
  : "${MYSQL_PASSWORD:?MYSQL_PASSWORD .env içinde yok}"
  : "${NEXTCLOUD_ADMIN_USER:?NEXTCLOUD_ADMIN_USER .env içinde yok}"
  : "${NEXTCLOUD_ADMIN_PASSWORD:?NEXTCLOUD_ADMIN_PASSWORD .env içinde yok}"
  mkdir -p /mnt/nextcloud/data
  admin_dir="/mnt/nextcloud/data/${NEXTCLOUD_ADMIN_USER}"
  if [[ -e "$admin_dir" ]]; then
    ts="$(date +%Y%m%d-%H%M%S)"
    backup="/mnt/nextcloud/data/${NEXTCLOUD_ADMIN_USER}.preinstall-backup-${ts}"
    echo "⚠️ Admin data dir mevcut ama Nextcloud kurulu değil. Silmeden yedeğe taşınıyor: $backup"
    mv "$admin_dir" "$backup"
  fi
  chown -R 33:33 /mnt/nextcloud/data
  chmod 750 /mnt/nextcloud/data
  occ maintenance:install \
    --database "mysql" \
    --database-name "$MYSQL_DATABASE" \
    --database-user "$MYSQL_USER" \
    --database-pass "$MYSQL_PASSWORD" \
    --database-host "db" \
    --admin-user "$NEXTCLOUD_ADMIN_USER" \
    --admin-pass "$NEXTCLOUD_ADMIN_PASSWORD"
  if ! occ_installed; then
    echo "❌ maintenance:install sonrası installed:true görülemedi."
    occ_status_text
    exit 1
  fi
  echo "✅ Nextcloud maintenance:install tamamlandı."
}

ensure_installed

if ! docker exec hb-nextcloud test -d /var/www/html/custom_apps >/dev/null 2>&1; then
  echo "❌ /var/www/html/custom_apps yok. Compose/volume mimarisini kontrol et."
  show_nc_logs
  exit 1
fi

echo "🔧 Nextcloud trusted domains / overwrite ayarları..."
occ config:system:set trusted_domains 0 --value='192.168.50.104'
occ config:system:set trusted_domains 1 --value='cloud.bacmastercloud.com'
occ config:system:set trusted_domains 2 --value='cloud-api.bacmastercloud.com'
occ config:system:delete overwritehost >/dev/null 2>&1 || true
occ config:system:delete overwriteprotocol >/dev/null 2>&1 || true
occ config:system:set overwrite.cli.url --value='http://192.168.50.104:8080'
occ maintenance:repair || true

echo "📦 Nextcloud data mount:"
docker exec hb-nextcloud df -h /var/www/html/data || true
REMOTE
chmod +x "$TMP/nextcloud-install-gate-and-local-fix.sh"
rscp "$TMP/nextcloud-install-gate-and-local-fix.sh" 104 /tmp/hv2313-nextcloud-local-fix.sh
rssh 104 "sudo bash /tmp/hv2313-nextcloud-local-fix.sh"
