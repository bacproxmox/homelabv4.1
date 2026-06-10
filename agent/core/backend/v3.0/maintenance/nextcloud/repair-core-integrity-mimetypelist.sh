#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "repair-nextcloud-core-integrity-mimetypelist"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"

cat <<'BANNER'
=========================================
 Repair Bacscloud core integrity warning
=========================================
This repairs the known INVALID_HASH warning for:
  core/js/mimetypelist.js

It restores the file from the official Nextcloud image source path inside the
container and then runs `occ integrity:check-core`.
BANNER

TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
cat > "$TMP" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /opt/homelab/nextcloud || { echo "❌ /opt/homelab/nextcloud yok"; exit 1; }

if ! docker ps --format '{{.Names}}' | grep -qx hb-nextcloud; then
  echo "❌ hb-nextcloud çalışmıyor."
  docker ps -a --filter name=hb-nextcloud || true
  exit 1
fi

occ(){ docker exec -u www-data hb-nextcloud php occ "$@"; }

echo "📋 Mevcut integrity sonucu:"
occ integrity:check-core || true

echo
found=0
for rel in core/js/mimetypelist.js core/js/mimetypeList.js; do
  src="/usr/src/nextcloud/${rel}"
  dst="/var/www/html/${rel}"
  if docker exec -u root hb-nextcloud test -f "$src"; then
    echo "🔧 Restore: $rel"
    docker exec -u root hb-nextcloud bash -lc "set -e; cp '$src' '$dst'; chown www-data:www-data '$dst'; chmod 644 '$dst'"
    found=1
  fi
done

if [[ "$found" != "1" ]]; then
  echo "❌ Official image source altında mimetypelist dosyası bulunamadı."
  docker exec -u root hb-nextcloud bash -lc "find /usr/src/nextcloud/core/js /var/www/html/core/js -maxdepth 1 -iname '*mime*list*.js' -ls" || true
  exit 1
fi

echo
# Clear opcode caches if possible; harmless if unavailable.
docker exec -u www-data hb-nextcloud php -r 'if (function_exists("opcache_reset")) { opcache_reset(); }' || true

echo "📋 Repair sonrası integrity sonucu:"
if occ integrity:check-core; then
  echo "✅ Core integrity temiz görünüyor."
else
  echo "⚠️ Hâlâ integrity uyarısı var. Yukarıdaki çıktıya göre değerlendir."
  exit 1
fi
REMOTE
chmod +x "$TMP"
rscp "$TMP" 104 /tmp/repair-nextcloud-core-integrity-mimetypelist.sh
rssh 104 "sudo bash /tmp/repair-nextcloud-core-integrity-mimetypelist.sh"
