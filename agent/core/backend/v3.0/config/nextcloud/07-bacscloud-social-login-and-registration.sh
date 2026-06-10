#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "bacscloud-social-login-registration"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"

SOCIAL_ENV="$SECRETS_DIR/nextcloud-sociallogin.env"
GOOGLE_ENV="$SECRETS_DIR/google.env"
[[ -f "$SOCIAL_ENV" ]] && source "$SOCIAL_ENV" || true
[[ -f "$GOOGLE_ENV" ]] && source "$GOOGLE_ENV" || true
NEXTCLOUD_GOOGLE_CLIENT_ID="${NEXTCLOUD_GOOGLE_CLIENT_ID:-${GOOGLE_CLIENT_ID:-}}"
NEXTCLOUD_GOOGLE_CLIENT_SECRET="${NEXTCLOUD_GOOGLE_CLIENT_SECRET:-${GOOGLE_CLIENT_SECRET:-}}"
NEXTCLOUD_REGISTRATION_ENABLED="${NEXTCLOUD_REGISTRATION_ENABLED:-true}"
NEXTCLOUD_REGISTRATION_APPROVAL_REQUIRED="${NEXTCLOUD_REGISTRATION_APPROVAL_REQUIRED:-true}"
NEXTCLOUD_REGISTRATION_ALLOWED_DOMAINS="${NEXTCLOUD_REGISTRATION_ALLOWED_DOMAINS:-gmail.com,googlemail.com,bacmastercloud.com}"
NEXTCLOUD_DEFAULT_USER_QUOTA="${NEXTCLOUD_DEFAULT_USER_QUOTA:-5 GB}"
TMP="$(mktemp -d)"
cat > "$TMP/env" <<ENV
NEXTCLOUD_GOOGLE_CLIENT_ID='${NEXTCLOUD_GOOGLE_CLIENT_ID}'
NEXTCLOUD_GOOGLE_CLIENT_SECRET='${NEXTCLOUD_GOOGLE_CLIENT_SECRET}'
NEXTCLOUD_REGISTRATION_ENABLED='${NEXTCLOUD_REGISTRATION_ENABLED}'
NEXTCLOUD_REGISTRATION_APPROVAL_REQUIRED='${NEXTCLOUD_REGISTRATION_APPROVAL_REQUIRED}'
NEXTCLOUD_REGISTRATION_ALLOWED_DOMAINS='${NEXTCLOUD_REGISTRATION_ALLOWED_DOMAINS}'
NEXTCLOUD_DEFAULT_USER_QUOTA='${NEXTCLOUD_DEFAULT_USER_QUOTA}'
ENV
chmod 600 "$TMP/env"
cat > "$TMP/apply.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
source /tmp/bacscloud-social.env
occ(){ docker exec -u www-data hb-nextcloud php occ "$@"; }

echo "👥 Groups/quota policy..."
occ group:add bacscloud-users >/dev/null 2>&1 || true
occ group:add bacscloud-pending >/dev/null 2>&1 || true
occ config:app:set files default_quota --value="$NEXTCLOUD_DEFAULT_USER_QUOTA" >/dev/null || true

echo "🔐 Social Login app..."
occ app:install sociallogin >/dev/null 2>&1 || true
occ app:enable sociallogin >/dev/null 2>&1 || true
occ config:app:set sociallogin hide_default_login --value="0" >/dev/null || true
occ config:app:set sociallogin prevent_create_email_exists --value="0" >/dev/null || true
occ config:app:set sociallogin update_profile_on_login --value="1" >/dev/null || true
occ config:app:set sociallogin disable_registration --value="0" >/dev/null || true
if [[ -n "$NEXTCLOUD_GOOGLE_CLIENT_ID" && -n "$NEXTCLOUD_GOOGLE_CLIENT_SECRET" ]]; then
  providers="$(jq -n --arg id "$NEXTCLOUD_GOOGLE_CLIENT_ID" --arg secret "$NEXTCLOUD_GOOGLE_CLIENT_SECRET" '{custom_oidc:[{name:"google",title:"Google ile giriş yap",authorizeUrl:"https://accounts.google.com/o/oauth2/v2/auth",tokenUrl:"https://oauth2.googleapis.com/token",userInfoUrl:"https://openidconnect.googleapis.com/v1/userinfo",logoutUrl:"",clientId:$id,clientSecret:$secret,scope:"openid email profile",groupsClaim:"",style:"google",defaultGroup:"bacscloud-users"}]}')"
  occ config:app:set sociallogin custom_providers --value="$providers" >/dev/null
  echo "✅ Google Social Login provider yazıldı. Secret loglanmadı."
else
  echo "⚠️ Google Client ID/Secret boş; login butonu yapılandırılmadı."
fi

echo "📝 Registration app..."
if [[ "$NEXTCLOUD_REGISTRATION_ENABLED" == "true" ]]; then
  occ app:install registration >/dev/null 2>&1 || true
  occ app:enable registration >/dev/null 2>&1 || true
  occ config:app:set registration registered_user_group --value="bacscloud-pending" >/dev/null || true
  occ config:app:set registration allowed_domains --value="$NEXTCLOUD_REGISTRATION_ALLOWED_DOMAINS" >/dev/null || true
  occ config:app:set registration admin_approval_required --value="$NEXTCLOUD_REGISTRATION_APPROVAL_REQUIRED" >/dev/null || true
  occ config:app:set registration email_is_login --value="0" >/dev/null || true
  echo "✅ Registration hazır: group=bacscloud-pending, allowed_domains=$NEXTCLOUD_REGISTRATION_ALLOWED_DOMAINS"
else
  occ app:disable registration >/dev/null 2>&1 || true
  echo "ℹ️ Registration disabled."
fi

docker restart hb-nextcloud >/dev/null || true
sleep 8
occ app:list | grep -E 'sociallogin|registration' || true
REMOTE
chmod +x "$TMP/apply.sh"
rscp "$TMP/env" 104 /tmp/bacscloud-social.env
rscp "$TMP/apply.sh" 104 /tmp/bacscloud-social-apply.sh
rssh 104 "sudo bash /tmp/bacscloud-social-apply.sh; sudo rm -f /tmp/bacscloud-social.env /tmp/bacscloud-social-apply.sh"
rm -rf "$TMP"
