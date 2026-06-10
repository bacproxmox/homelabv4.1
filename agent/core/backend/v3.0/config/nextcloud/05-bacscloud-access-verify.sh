#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "bacscloud-access-verify"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"

echo
echo "🔎 Bacscloud / Nextcloud erişim doğrulaması"
echo "ℹ️ Local LAN erişim HTTP olmalı: http://192.168.50.104:8080"
echo "ℹ️ https://192.168.50.104:8080 beklenmez; HTTPS Cloudflare URL üzerinde sağlanır."

TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
cat > "$TMP" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /opt/homelab/nextcloud || { echo "❌ /opt/homelab/nextcloud yok"; exit 1; }

show_debug(){
  echo "--- docker ps ---"; docker ps -a --filter name=hb-nextcloud || true
  echo "--- logs hb-nextcloud ---"; docker logs hb-nextcloud --tail=120 || true
  echo "--- compose ps ---"; docker compose ps || true
  echo "--- local ports ---"; ss -ltnp | grep -E '(:8080|:80)' || true
}

if ! docker ps --format '{{.Names}}' | grep -qx 'hb-nextcloud'; then
  echo "❌ hb-nextcloud container çalışmıyor."
  show_debug
  exit 1
fi

occ(){ docker exec -u www-data hb-nextcloud php occ "$@"; }
if ! occ status >/tmp/nc-status.txt 2>&1; then
  echo "❌ occ status çalışmadı."
  cat /tmp/nc-status.txt || true
  show_debug
  exit 1
fi
cat /tmp/nc-status.txt
if ! grep -q 'installed:[[:space:]]*true' /tmp/nc-status.txt; then
  echo "❌ Nextcloud installed:true değil."
  show_debug
  exit 1
fi

# Keep direct LAN access trusted even after Cloudflare hardening.
occ config:system:set trusted_domains 0 --value="192.168.50.104" >/dev/null || true
occ config:system:set trusted_domains 1 --value="cloud.bacmastercloud.com" >/dev/null || true
occ config:system:set trusted_domains 2 --value="cloud-api.bacmastercloud.com" >/dev/null || true
occ config:system:set trusted_domains 3 --value="192.168.50.104:8080" >/dev/null || true

for url in \
  http://127.0.0.1:8080/status.php \
  http://192.168.50.104:8080/status.php
 do
  echo "⏳ Test: $url"
  ok=0
  for i in $(seq 1 45); do
    body="$(curl -fsS --connect-timeout 3 --max-time 10 "$url" 2>/tmp/nc-curl.err || true)"
    if echo "$body" | grep -q '"installed"[[:space:]]*:[[:space:]]*true'; then
      echo "✅ Erişim OK: $url"
      ok=1
      break
    fi
    sleep 2
  done
  if [[ "$ok" != "1" ]]; then
    echo "❌ Erişim testi başarısız: $url"
    cat /tmp/nc-curl.err || true
    show_debug
    exit 1
  fi
 done

echo "✅ Bacscloud local erişim doğrulandı: http://192.168.50.104:8080"
echo "ℹ️ Public Cloudflare URL kontrolü final Cloudflared aşamasından sonra yapılmalı:"
echo "   https://cloud.bacmastercloud.com"
echo "   https://cloud-api.bacmastercloud.com"
REMOTE
chmod +x "$TMP"
rscp "$TMP" 104 /tmp/homelab-bacscloud-access-verify.sh
rssh 104 "sudo bash /tmp/homelab-bacscloud-access-verify.sh"
