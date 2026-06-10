#!/usr/bin/env bash
set -Eeuo pipefail
set +H

echo "🔐 Homelab v2.4.7 - Google OAuth Manager"
echo "🩹 Hotfix: safe env loading + Open WebUI heredoc fix"

SECRETS_DIR="/root/homelab-secrets"
USERS_ENV="$SECRETS_DIR/users.env"
GOOGLE_ENV="$SECRETS_DIR/google.env"
LEGACY_OAUTH_ENV="$SECRETS_DIR/oauth.env"

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

[[ -f "$USERS_ENV" ]] || { echo "❌ users.env yok: $USERS_ENV"; exit 1; }

# shellcheck disable=SC1090
source "$USERS_ENV"
[[ -f "$GOOGLE_ENV" ]] && source "$GOOGLE_ENV"
[[ -f "$LEGACY_OAUTH_ENV" ]] && source "$LEGACY_OAUTH_ENV"

ask_visible_if_missing() {
  local var_name="$1"
  local prompt="$2"
  local current=""

  # Indirect expansion must happen after var_name exists.
  current="${!var_name:-}"

  if [[ -n "$current" ]]; then
    echo "✅ $var_name mevcut, tekrar sorulmayacak."
    return 0
  fi

  local value=""
  while [[ -z "$value" ]]; do
    read -r -p "$prompt: " value
  done

  printf -v "$var_name" '%s' "$value"
}

ask_visible_if_missing GOOGLE_CLIENT_ID "Google Client ID"
ask_visible_if_missing GOOGLE_CLIENT_SECRET "Google Client Secret"

# Guided/one-button install must not stop for this prompt.
# Default is true; disable later with maintenance/auth/disable-google-auto-register.sh if desired.
if [[ -z "${GOOGLE_AUTO_REGISTER:-}" ]]; then
  GOOGLE_AUTO_REGISTER="true"
  echo "✅ Google ile otomatik kayıt varsayılan olarak açık: GOOGLE_AUTO_REGISTER=true"
fi

cat > "$GOOGLE_ENV" <<ENV
GOOGLE_CLIENT_ID='${GOOGLE_CLIENT_ID}'
GOOGLE_CLIENT_SECRET='${GOOGLE_CLIENT_SECRET}'
GOOGLE_ISSUER_URL='https://accounts.google.com'
GOOGLE_SCOPE='openid email profile'
GOOGLE_AUTO_REGISTER='${GOOGLE_AUTO_REGISTER}'
ENV
chmod 600 "$GOOGLE_ENV"
ln -sf "$GOOGLE_ENV" "$LEGACY_OAUTH_ENV" 2>/dev/null || true
echo "✅ Google OAuth secret kaydedildi: $GOOGLE_ENV"

VM106_IP="192.168.50.106"
VM104_IP="192.168.50.104"
SSH_USER="${BACMASTER_USER:-bacmaster}"
SSH_PASS="${BACMASTER_PASS:?BACMASTER_PASS yok}"
IMMICH_AUTO_REGISTER="$GOOGLE_AUTO_REGISTER"
OPENWEBUI_SIGNUP="$GOOGLE_AUTO_REGISTER"

apt update
apt install -y sshpass curl jq

shell_quote() {
  printf "%q" "$1"
}

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

run_remote_script() {
  local ip="$1"
  local envs="$2"
  local local_script="$3"

  sshpass -p "$SSH_PASS" scp "${SSH_OPTS[@]}" "$local_script" "$SSH_USER@$ip:/tmp/homelab-oauth.sh" >/dev/null
  sshpass -p "$SSH_PASS" ssh "${SSH_OPTS[@]}" "$SSH_USER@$ip" \
    "printf '%s\n' $(shell_quote "$SSH_PASS") | sudo -S -p '' env $envs bash /tmp/homelab-oauth.sh"
}

make_tmp_script() {
  local tmp
  tmp="$(mktemp)"
  cat > "$tmp"
  chmod +x "$tmp"
  printf '%s' "$tmp"
}

echo
echo "📸 Immich OAuth ayarlanıyor..."
IMMICH_SCRIPT="$(make_tmp_script <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail

cd /opt/homelab/immich

LOGIN_JSON="$(curl -sS -X POST http://127.0.0.1:2283/api/auth/login \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"admin@bacmastercloud.com\",\"password\":\"$BACMASTER_PASS\"}")"

TOKEN="$(echo "$LOGIN_JSON" | jq -r ".accessToken // empty")"
[[ -n "$TOKEN" ]] || {
  echo "❌ Immich admin token alınamadı."
  echo "$LOGIN_JSON"
  exit 1
}

CONFIG="$(curl -sS http://127.0.0.1:2283/api/system-config -H "Authorization: Bearer $TOKEN")"

NEW_CONFIG="$(echo "$CONFIG" | jq \
  --arg clientId "$GOOGLE_CLIENT_ID" \
  --arg clientSecret "$GOOGLE_CLIENT_SECRET" \
  --argjson autoRegister "$IMMICH_AUTO_REGISTER" \
  '.oauth.enabled=true
   | .oauth.issuerUrl="https://accounts.google.com"
   | .oauth.clientId=$clientId
   | .oauth.clientSecret=$clientSecret
   | .oauth.scope="openid email profile"
   | .oauth.signingAlgorithm="RS256"
   | .oauth.profileSigningAlgorithm="none"
   | .oauth.storageLabelClaim="email"
   | .oauth.buttonText="Google ile giriş yap"
   | .oauth.autoRegister=$autoRegister
   | .oauth.autoLaunch=false')"

curl -sS -X PUT http://127.0.0.1:2283/api/system-config \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "$NEW_CONFIG" >/dev/null

docker compose restart immich-server >/dev/null
echo "✅ Immich OAuth tamam."
REMOTE
)"

run_remote_script "$VM106_IP" \
  "BACMASTER_PASS=$(shell_quote "$SSH_PASS") GOOGLE_CLIENT_ID=$(shell_quote "$GOOGLE_CLIENT_ID") GOOGLE_CLIENT_SECRET=$(shell_quote "$GOOGLE_CLIENT_SECRET") IMMICH_AUTO_REGISTER=$(shell_quote "$IMMICH_AUTO_REGISTER")" \
  "$IMMICH_SCRIPT"
rm -f "$IMMICH_SCRIPT"

echo
echo "🤖 Open WebUI OAuth ayarlanıyor..."
OPENWEBUI_SCRIPT="$(make_tmp_script <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail

cd /opt/homelab/ollama

[[ -f docker-compose.yml ]] || {
  echo "❌ docker-compose.yml yok: /opt/homelab/ollama/docker-compose.yml"
  exit 1
}

python3 <<'PY'
import os
from pathlib import Path

p = Path("docker-compose.yml")
text = p.read_text()

remove_keys = [
    "OAUTH_CLIENT_ID=",
    "OAUTH_CLIENT_SECRET=",
    "OPENID_PROVIDER_URL=",
    "ENABLE_OAUTH_SIGNUP=",
    "OAUTH_PROVIDER_NAME=",
    "OAUTH_SCOPES=",
    "OPENID_REDIRECT_URI=",
    "WEBUI_URL=",
]

lines = []
for line in text.splitlines():
    if any(k in line for k in remove_keys):
        continue
    lines.append(line)

insert = [
    f"      - OAUTH_CLIENT_ID={os.environ['GOOGLE_CLIENT_ID']}",
    f"      - OAUTH_CLIENT_SECRET={os.environ['GOOGLE_CLIENT_SECRET']}",
    "      - OPENID_PROVIDER_URL=https://accounts.google.com/.well-known/openid-configuration",
    f"      - ENABLE_OAUTH_SIGNUP={os.environ.get('OPENWEBUI_SIGNUP', 'false')}",
    "      - OAUTH_PROVIDER_NAME=Google",
    "      - OAUTH_SCOPES=openid email profile",
    "      - OPENID_REDIRECT_URI=https://ai.bacmastercloud.com/oauth/oidc/callback",
    "      - WEBUI_URL=https://ai.bacmastercloud.com",
]

marker = "      - OLLAMA_BASE_URL=http://ollama:11434"
out = "\n".join(lines)

if marker in out:
    out = out.replace(marker, "\n".join(insert) + "\n" + marker)
else:
    # Find the open-webui service environment block. If not found, append to the first environment block.
    target = "    environment:\n"
    if target in out:
        out = out.replace(target, target + "\n".join(insert) + "\n", 1)
    else:
        raise SystemExit("docker-compose.yml içinde environment bloğu bulunamadı.")

p.write_text(out.rstrip() + "\n")
PY

docker compose up -d >/dev/null
docker compose restart open-webui >/dev/null || docker restart hb-openwebui >/dev/null
echo "✅ Open WebUI OAuth tamam."
REMOTE
)"

run_remote_script "$VM106_IP" \
  "GOOGLE_CLIENT_ID=$(shell_quote "$GOOGLE_CLIENT_ID") GOOGLE_CLIENT_SECRET=$(shell_quote "$GOOGLE_CLIENT_SECRET") OPENWEBUI_SIGNUP=$(shell_quote "$OPENWEBUI_SIGNUP")" \
  "$OPENWEBUI_SCRIPT"
rm -f "$OPENWEBUI_SCRIPT"

echo
echo "☁️ Nextcloud Social Login hazırlanıyor..."
NEXTCLOUD_SCRIPT="$(make_tmp_script <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail

cd /opt/homelab/nextcloud || {
  echo "⚠️ Nextcloud klasörü yok, Nextcloud OAuth atlanıyor."
  exit 0
}

if ! docker ps --format '{{.Names}}' | grep -qx 'hb-nextcloud'; then
  echo "⚠️ hb-nextcloud çalışmıyor, Nextcloud OAuth atlanıyor."
  exit 0
fi

if ! docker exec -u www-data hb-nextcloud php occ status >/dev/null 2>&1; then
  echo "⚠️ Nextcloud OCC hazır değil, Nextcloud OAuth atlanıyor."
  exit 0
fi

docker exec -u www-data hb-nextcloud php occ app:install sociallogin >/dev/null 2>&1 || true
docker exec -u www-data hb-nextcloud php occ app:enable sociallogin >/dev/null 2>&1 || true

# Conservative basic settings; provider JSON schema can vary by Social Login version,
# so do not hard-fail the full homelab config if this app changes.
docker exec -u www-data hb-nextcloud php occ config:app:set sociallogin prevent_create_email_exists --value=1 >/dev/null 2>&1 || true
docker exec -u www-data hb-nextcloud php occ config:app:set sociallogin update_profile_on_login --value=1 >/dev/null 2>&1 || true

echo "✅ Nextcloud Social Login app hazırlandı."
echo "ℹ️ Google provider gerekirse UI’dan doğrulanmalı: https://cloud.bacmastercloud.com/settings/admin/sociallogin"
REMOTE
)"

run_remote_script "$VM104_IP" \
  "GOOGLE_CLIENT_ID=$(shell_quote "$GOOGLE_CLIENT_ID") GOOGLE_CLIENT_SECRET=$(shell_quote "$GOOGLE_CLIENT_SECRET") GOOGLE_AUTO_REGISTER=$(shell_quote "$GOOGLE_AUTO_REGISTER")" \
  "$NEXTCLOUD_SCRIPT"
rm -f "$NEXTCLOUD_SCRIPT"

echo
echo "✅ Google OAuth manager tamamlandı."
echo "Kontrol:"
echo "  Immich     : https://photos.bacmastercloud.com"
echo "  Open WebUI : https://ai.bacmastercloud.com"
echo "  Nextcloud  : https://cloud.bacmastercloud.com"
