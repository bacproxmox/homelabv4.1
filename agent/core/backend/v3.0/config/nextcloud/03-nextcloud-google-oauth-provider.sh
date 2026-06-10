#!/usr/bin/env bash
set -Eeuo pipefail
set +H

echo
echo "🔐 Homelab v2.4.7 - Nextcloud Google Social Login Provider"
echo

source /root/homelab-secrets/users.env

OAUTH_ENV="/root/homelab-secrets/oauth.env"
mkdir -p /root/homelab-secrets
chmod 700 /root/homelab-secrets

if [[ -f "$OAUTH_ENV" ]]; then
  source "$OAUTH_ENV"
fi

if [[ -z "${GOOGLE_CLIENT_ID:-}" ]]; then
  read -r -p "Google Client ID: " GOOGLE_CLIENT_ID
fi

if [[ -z "${GOOGLE_CLIENT_SECRET:-}" ]]; then
  read -r -p "Google Client Secret: " GOOGLE_CLIENT_SECRET
fi

cat > "$OAUTH_ENV" <<ENV
GOOGLE_CLIENT_ID='${GOOGLE_CLIENT_ID}'
GOOGLE_CLIENT_SECRET='${GOOGLE_CLIENT_SECRET}'
GOOGLE_ISSUER_URL='https://accounts.google.com'
GOOGLE_SCOPE='openid email profile'
ENV
chmod 600 "$OAUTH_ENV"

VM104_IP="192.168.50.104"
SSH_USER="${BACMASTER_USER:-bacmaster}"
SSH_PASS="${BACMASTER_PASS:?BACMASTER_PASS yok}"

apt update
apt install -y sshpass jq curl

shell_quote(){ printf "%q" "$1"; }

TMP="$(mktemp)"

cat > "$TMP" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
set +H

apt update >/dev/null
apt install -y jq >/dev/null

cd /opt/homelab/nextcloud

occ() {
  docker exec -u www-data hb-nextcloud php occ "$@"
}

echo
echo "🧪 Nextcloud kontrol..."
occ status

echo
echo "📦 Social Login app kuruluyor/aktif ediliyor..."
occ app:install sociallogin || true
occ app:enable sociallogin || true

echo
echo "🌐 Reverse proxy URL garantiye alınıyor..."
occ config:system:set overwrite.cli.url --value="https://cloud.bacmastercloud.com"
occ config:system:set overwritehost --value="cloud.bacmastercloud.com"
occ config:system:set overwriteprotocol --value="https"
occ config:system:set trusted_domains 0 --value="192.168.50.104"
occ config:system:set trusted_domains 1 --value="192.168.50.104:8080"
occ config:system:set trusted_domains 2 --value="cloud.bacmastercloud.com"
occ config:system:set trusted_domains 3 --value="nextcloud.bacmastercloud.com"
occ config:system:set trusted_domains 4 --value="cloud-api.bacmastercloud.com"
occ config:system:set trusted_domains 5 --value="localhost"
occ config:system:set trusted_domains 6 --value="127.0.0.1"
occ config:system:set trusted_proxies 0 --value="192.168.50.103" >/dev/null || true
occ config:system:set trusted_proxies 1 --value="172.16.0.0/12" >/dev/null || true
occ config:system:set trusted_proxies 2 --value="10.0.0.0/8" >/dev/null || true
occ config:system:set trusted_proxies 3 --value="192.168.0.0/16" >/dev/null || true

echo
echo "🔐 Social Login genel ayarları uygulanıyor..."
occ config:app:set sociallogin prevent_create_email_exists --value="0"
occ config:app:set sociallogin update_profile_on_login --value="1"
occ config:app:set sociallogin auto_create_groups --value="0"
occ config:app:set sociallogin hide_default_login --value="0"
occ config:app:set sociallogin disable_registration --value="0"

echo
echo "🔑 Google Custom OIDC provider yazılıyor..."

PROVIDERS="$(jq -n \
  --arg clientId "$GOOGLE_CLIENT_ID" \
  --arg clientSecret "$GOOGLE_CLIENT_SECRET" \
  '{
    custom_oidc: [
      {
        name: "google",
        title: "Google ile giriş yap",
        authorizeUrl: "https://accounts.google.com/o/oauth2/v2/auth",
        tokenUrl: "https://oauth2.googleapis.com/token",
        userInfoUrl: "https://openidconnect.googleapis.com/v1/userinfo",
        logoutUrl: "",
        clientId: $clientId,
        clientSecret: $clientSecret,
        scope: "openid email profile",
        groupsClaim: "",
        style: "google",
        defaultGroup: ""
      }
    ]
  }')"

occ config:app:set sociallogin custom_providers --value="$PROVIDERS" >/dev/null

echo
echo "🔄 Nextcloud restart..."
docker compose restart nextcloud >/dev/null

sleep 8

echo
echo "📋 Kontrol:"
echo "custom_providers yazıldı (secret redacted)."

echo
echo "✅ Nextcloud Google Social Login provider tamamlandı."
echo "Kontrol: https://cloud.bacmastercloud.com/login"
REMOTE

sshpass -p "$SSH_PASS" scp \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  "$TMP" "$SSH_USER@$VM104_IP:/tmp/nextcloud-google-oauth-provider.sh" >/dev/null

sshpass -p "$SSH_PASS" ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  "$SSH_USER@$VM104_IP" \
  "printf '%s\n' $(shell_quote "$SSH_PASS") | sudo -S -p '' env \
GOOGLE_CLIENT_ID=$(shell_quote "$GOOGLE_CLIENT_ID") \
GOOGLE_CLIENT_SECRET=$(shell_quote "$GOOGLE_CLIENT_SECRET") \
bash /tmp/nextcloud-google-oauth-provider.sh"

rm -f "$TMP"

echo
echo "✅ 12h-nextcloud-google-oauth-provider.sh tamamlandı."
