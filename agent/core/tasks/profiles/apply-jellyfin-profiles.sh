#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"
while [[ ! -f "$ROOT_DIR/bin/homelab" && "$ROOT_DIR" != "/" ]]; do
  ROOT_DIR="$(cd "$ROOT_DIR/.." && pwd)"
done
[[ -f "$ROOT_DIR/bin/homelab" ]] || { echo "Hata: bin/homelab bulunamadi." >&2; exit 127; }

export HOMELAB_ROOT="$ROOT_DIR"
source "$HOMELAB_ROOT/lib/core/env.sh"
source "$HOMELAB_ROOT/lib/core/env-write.sh"
source "$HOMELAB_ROOT/lib/remote/password-ssh.sh"
load_all_env

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

{
  write_env_header
  write_env_line BACMASTER_USER "${BACMASTER_USER:-bacmaster}"
  write_env_line BACMASTER_PASS "${BACMASTER_PASS:-}"
  write_env_line ATLON_PASS "${ATLON_PASS:-}"
  write_env_line ELIFEZEL_PASS "${ELIFEZEL_PASS:-}"
  write_env_line TULUMBA_PASS "${TULUMBA_PASS:-}"
  write_env_line JELLYFIN_BRAND "${JELLYFIN_BRAND:-Bacsflix}"
  write_env_line BACMASTER_AVATAR_URL "${BACMASTER_AVATAR_URL:-}"
  write_env_line ATLON_AVATAR_URL "${ATLON_AVATAR_URL:-}"
  write_env_line ELIFEZEL_AVATAR_URL "${ELIFEZEL_AVATAR_URL:-}"
  write_env_line TULUMBA_AVATAR_URL "${TULUMBA_AVATAR_URL:-}"
} > "$TMP/jellyfin-profiles.env"

cat > "$TMP/apply-jellyfin-profiles.remote.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail

JELLYFIN_URL="http://127.0.0.1:8096"
ADMIN_USER="${BACMASTER_USER:-bacmaster}"
ADMIN_PASS="${BACMASTER_PASS:-}"
BRAND="${JELLYFIN_BRAND:-Bacsflix}"

[[ -n "$ADMIN_PASS" ]] || { echo "BACMASTER_PASS yok; Jellyfin profil task'i atlandi."; exit 1; }

if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1 || ! command -v file >/dev/null 2>&1; then
  apt-get update >/dev/null
  apt-get install -y jq curl file >/dev/null
fi

for _ in $(seq 1 60); do
  curl -fsS "$JELLYFIN_URL/System/Info/Public" >/dev/null 2>&1 && break
  sleep 3
done

auth="$(curl -sS -X POST "$JELLYFIN_URL/Users/authenticatebyname" \
  -H "Content-Type: application/json" \
  -H 'X-Emby-Authorization: MediaBrowser Client="homelab-v3.1", Device="profiles", DeviceId="homelab-v31-profiles", Version="3.1"' \
  --data "$(jq -n --arg u "$ADMIN_USER" --arg p "$ADMIN_PASS" '{Username:$u,Pw:$p}')" || true)"

if ! echo "$auth" | jq empty >/dev/null 2>&1; then
  echo "Jellyfin auth JSON donmedi; wizard/admin hazir olmayabilir."
  exit 20
fi

token="$(echo "$auth" | jq -r '.AccessToken // empty')"
[[ -n "$token" && "$token" != "null" ]] || { echo "Jellyfin admin login basarisiz."; exit 20; }

auth_header="X-Emby-Token: $token"

server_config="$(curl -sS -H "$auth_header" "$JELLYFIN_URL/System/Configuration" || echo '{}')"
if echo "$server_config" | jq empty >/dev/null 2>&1; then
  echo "$server_config" | jq --arg brand "$BRAND" '.ServerName=$brand' >/tmp/jellyfin-server-config.json
  curl -sS -X POST -H "$auth_header" -H "Content-Type: application/json" \
    "$JELLYFIN_URL/System/Configuration" --data @/tmp/jellyfin-server-config.json >/dev/null || true
fi

ensure_user() {
  local name="$1" pass="$2" role="$3" user_id users policy updated
  [[ -n "$name" ]] || return 0
  users="$(curl -sS -H "$auth_header" "$JELLYFIN_URL/Users" || echo '[]')"
  user_id="$(echo "$users" | jq -r --arg name "$name" '.[]? | select((.Name|ascii_downcase)==($name|ascii_downcase)) | .Id' | head -n1)"
  if [[ -z "$user_id" && -n "$pass" ]]; then
    echo "Jellyfin kullanici olusturuluyor: $name" >&2
    created="$(curl -sS -X POST -H "$auth_header" -H "Content-Type: application/json" \
      "$JELLYFIN_URL/Users/New" --data "$(jq -n --arg n "$name" --arg p "$pass" '{Name:$n,Password:$p}')" || true)"
    user_id="$(echo "$created" | jq -r '.Id // empty' 2>/dev/null || true)"
  fi
  [[ -n "$user_id" && "$user_id" != "null" ]] || { echo "Jellyfin kullanici bulunamadi/olusturulamadi: $name" >&2; return 0; }

  if [[ "$role" == "viewer" ]]; then
    policy="$(curl -sS -H "$auth_header" "$JELLYFIN_URL/Users/$user_id/Policy" || echo '{}')"
    if echo "$policy" | jq empty >/dev/null 2>&1; then
      updated="$(echo "$policy" | jq '
        .IsAdministrator=false |
        .IsHidden=false |
        .IsDisabled=false |
        .EnableUserPreferenceAccess=true |
        .EnableRemoteAccess=true |
        .EnableLiveTvAccess=false |
        .EnableMediaPlayback=true |
        .EnableAudioPlaybackTranscoding=true |
        .EnableVideoPlaybackTranscoding=true |
        .EnablePlaybackRemuxing=true |
        .EnableContentDeletion=false |
        .EnableContentDownloading=false |
        .EnableAllDevices=true |
        .EnableAllChannels=true |
        .EnableAllFolders=true
      ')"
      curl -sS -X POST -H "$auth_header" -H "Content-Type: application/json" \
        "$JELLYFIN_URL/Users/$user_id/Policy" --data "$updated" >/dev/null || true
    fi
  fi

  printf '%s' "$user_id"
}

apply_avatar() {
  local name="$1" url="$2" user_id="$3" file mime
  [[ -n "$url" && -n "$user_id" ]] || return 0
  file="/tmp/homelab-avatar-${name}.img"
  if ! curl -fsSL "$url" -o "$file"; then
    echo "Avatar indirilemedi: $name -> $url"
    return 0
  fi
  mime="$(file -b --mime-type "$file" 2>/dev/null || echo image/png)"
  case "$mime" in image/png|image/jpeg|image/webp|image/gif) ;; *) mime="image/png" ;; esac
  curl -fsS -X POST -H "$auth_header" -H "Content-Type: $mime" \
    --data-binary "@$file" "$JELLYFIN_URL/Users/$user_id/Images/Primary" >/dev/null || {
      echo "Jellyfin avatar uygulanamadi: $name"
      return 0
    }
  echo "Jellyfin avatar uygulandi: $name"
}

admin_id="$(ensure_user "$ADMIN_USER" "$ADMIN_PASS" admin)"
apply_avatar "$ADMIN_USER" "${BACMASTER_AVATAR_URL:-}" "$admin_id"

elifezel_id="$(ensure_user "Elifezel" "${ELIFEZEL_PASS:-}" viewer)"
apply_avatar "Elifezel" "${ELIFEZEL_AVATAR_URL:-}" "$elifezel_id"

atlon_id="$(ensure_user "Atlon" "${ATLON_PASS:-}" viewer)"
apply_avatar "Atlon" "${ATLON_AVATAR_URL:-}" "$atlon_id"

tulumba_id="$(ensure_user "Tulumba" "${TULUMBA_PASS:-}" viewer)"
apply_avatar "Tulumba" "${TULUMBA_AVATAR_URL:-}" "$tulumba_id"

echo "Jellyfin profilleri hazir: $BRAND"
REMOTE

password_rscp "$TMP/jellyfin-profiles.env" 106 /tmp/homelab-jellyfin-profiles.env
password_rscp "$TMP/apply-jellyfin-profiles.remote.sh" 106 /tmp/apply-jellyfin-profiles.remote.sh
password_sudo_bash 106 "set -a; source /tmp/homelab-jellyfin-profiles.env; set +a; bash /tmp/apply-jellyfin-profiles.remote.sh"
