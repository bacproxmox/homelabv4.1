#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "disable-google-auto-register"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"

shell_quote(){ printf "%q" "$1"; }

SECRETS_DIR="${SECRETS_DIR:-/root/homelab-secrets}"
GOOGLE_ENV="$SECRETS_DIR/google.env"
mkdir -p "$SECRETS_DIR"; chmod 700 "$SECRETS_DIR"
if [[ -f "$GOOGLE_ENV" ]]; then
  sed -i "s/^GOOGLE_AUTO_REGISTER=.*/GOOGLE_AUTO_REGISTER='false'/" "$GOOGLE_ENV" || true
  grep -q '^GOOGLE_AUTO_REGISTER=' "$GOOGLE_ENV" || echo "GOOGLE_AUTO_REGISTER='false'" >> "$GOOGLE_ENV"
else
  cat > "$GOOGLE_ENV" <<'ENV'
GOOGLE_AUTO_REGISTER='false'
ENV
fi
chmod 600 "$GOOGLE_ENV"
echo "✅ google.env içinde GOOGLE_AUTO_REGISTER=false yapıldı."

# Immich: disable OAuth autoRegister if reachable.
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
cat > "$TMP" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /opt/homelab/immich || exit 0
LOGIN_JSON="$(curl -sS -X POST http://127.0.0.1:2283/api/auth/login -H 'Content-Type: application/json' -d "{\"email\":\"admin@bacmastercloud.com\",\"password\":\"$BACMASTER_PASS\"}" || true)"
TOKEN="$(echo "$LOGIN_JSON" | jq -r '.accessToken // empty' 2>/dev/null || true)"
if [[ -n "$TOKEN" ]]; then
  CONFIG="$(curl -sS http://127.0.0.1:2283/api/system-config -H "Authorization: Bearer $TOKEN")"
  NEW_CONFIG="$(echo "$CONFIG" | jq '.oauth.autoRegister=false')"
  curl -sS -X PUT http://127.0.0.1:2283/api/system-config -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "$NEW_CONFIG" >/dev/null || true
  docker compose restart immich-server >/dev/null || true
  echo "✅ Immich OAuth autoRegister=false"
else
  echo "⚠️ Immich token alınamadı; atlandı."
fi
REMOTE
chmod +x "$TMP"
rscp "$TMP" 106 /tmp/homelab-disable-google-autoreg-immich.sh
rssh 106 "sudo env BACMASTER_PASS=$(shell_quote "${BACMASTER_PASS:-}") bash /tmp/homelab-disable-google-autoreg-immich.sh" || true

# Open WebUI: set ENABLE_OAUTH_SIGNUP=false in compose.
cat > "$TMP" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /opt/homelab/ollama || exit 0
if [[ -f docker-compose.yml ]]; then
  if grep -q 'ENABLE_OAUTH_SIGNUP=' docker-compose.yml; then
    sed -i 's/ENABLE_OAUTH_SIGNUP=.*/ENABLE_OAUTH_SIGNUP=false/' docker-compose.yml
  else
    echo "⚠️ ENABLE_OAUTH_SIGNUP yok; Open WebUI compose elle kontrol edilebilir."
  fi
  docker compose up -d >/dev/null || true
  docker compose restart open-webui >/dev/null || docker restart hb-openwebui >/dev/null || true
  echo "✅ Open WebUI ENABLE_OAUTH_SIGNUP=false"
fi
REMOTE
chmod +x "$TMP"
rscp "$TMP" 106 /tmp/homelab-disable-google-autoreg-openwebui.sh
rssh 106 "sudo bash /tmp/homelab-disable-google-autoreg-openwebui.sh" || true

echo "✅ Google auto-register disable işlemi tamamlandı."
