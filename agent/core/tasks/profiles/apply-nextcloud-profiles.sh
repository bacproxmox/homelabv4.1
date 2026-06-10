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
  write_env_line ATLON_USER "${ATLON_USER:-atlon}"
  write_env_line ATLON_PASS "${ATLON_PASS:-}"
  write_env_line ELIFEZEL_USER "${ELIFEZEL_USER:-elifezel}"
  write_env_line ELIFEZEL_PASS "${ELIFEZEL_PASS:-}"
  write_env_line TULUMBA_USER "${TULUMBA_USER:-tulumba}"
  write_env_line TULUMBA_PASS "${TULUMBA_PASS:-}"
  write_env_line NEXTCLOUD_BRAND "${NEXTCLOUD_BRAND:-Bacscloud}"
  write_env_line NEXTCLOUD_DEFAULT_USER_QUOTA "${NEXTCLOUD_DEFAULT_USER_QUOTA:-5 GB}"
  write_env_line BACMASTER_AVATAR_URL "${BACMASTER_AVATAR_URL:-}"
  write_env_line ATLON_AVATAR_URL "${ATLON_AVATAR_URL:-}"
  write_env_line ELIFEZEL_AVATAR_URL "${ELIFEZEL_AVATAR_URL:-}"
  write_env_line TULUMBA_AVATAR_URL "${TULUMBA_AVATAR_URL:-}"
} > "$TMP/nextcloud-profiles.env"

cat > "$TMP/apply-nextcloud-profiles.remote.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail

cd /opt/homelab/nextcloud || { echo "/opt/homelab/nextcloud yok"; exit 1; }
[[ -f .env ]] && { set -a; source .env; set +a; }

if ! command -v curl >/dev/null 2>&1; then
  apt-get update >/dev/null
  apt-get install -y curl >/dev/null
fi

occ() {
  docker exec -u www-data hb-nextcloud php occ "$@"
}

wait_ready() {
  for _ in $(seq 1 90); do
    docker exec hb-nextcloud test -f /var/www/html/version.php >/dev/null 2>&1 && return 0
    sleep 2
  done
  return 1
}

wait_ready || { echo "Nextcloud container hazir degil"; exit 1; }

if ! occ status 2>&1 | grep -q 'installed:[[:space:]]*true'; then
  echo "Nextcloud installed:true degil; profil task'i atlandi."
  exit 20
fi

brand="${NEXTCLOUD_BRAND:-Bacscloud}"
quota="${NEXTCLOUD_DEFAULT_USER_QUOTA:-5 GB}"

occ app:enable theming >/dev/null 2>&1 || true
occ config:app:set theming name --value="$brand" >/dev/null || true
occ config:app:set theming slogan --value="Homelab Cloud" >/dev/null || true
occ config:system:set default_phone_region --value="TR" >/dev/null || true

cat >/tmp/homelab-set-nextcloud-avatar.php <<'PHP'
<?php
if ($argc < 3) {
  fwrite(STDERR, "usage: set-avatar.php <uid> <file>\n");
  exit(2);
}
$uid = $argv[1];
$file = $argv[2];
require_once '/var/www/html/lib/base.php';
$data = @file_get_contents($file);
if ($data === false || strlen($data) === 0) {
  fwrite(STDERR, "avatar file empty\n");
  exit(3);
}
$avatar = \OC::$server->getAvatarManager()->getAvatar($uid);
$avatar->set($data);
echo "avatar-ok:$uid\n";
PHP
docker cp /tmp/homelab-set-nextcloud-avatar.php hb-nextcloud:/tmp/homelab-set-nextcloud-avatar.php >/dev/null || {
  echo "Uyari: Nextcloud avatar helper kopyalanamadi; avatar adimlari atlanabilir."
}

cat >/tmp/homelab-set-nextcloud-display.php <<'PHP'
<?php
if ($argc < 3) {
  fwrite(STDERR, "usage: set-display.php <uid> <display>\n");
  exit(2);
}
$uid = $argv[1];
$display = $argv[2];
require_once '/var/www/html/lib/base.php';
$user = \OC::$server->getUserManager()->get($uid);
if ($user === null) {
  fwrite(STDERR, "user not found\n");
  exit(3);
}
$user->setDisplayName($display);
echo "display-ok:$uid\n";
PHP
docker cp /tmp/homelab-set-nextcloud-display.php hb-nextcloud:/tmp/homelab-set-nextcloud-display.php >/dev/null || {
  echo "Uyari: Nextcloud display-name helper kopyalanamadi; display adimlari atlanabilir."
}

ensure_user() {
  local uid="$1" display="$2" pass="$3"
  [[ -n "$uid" && -n "$pass" ]] || return 0
  if occ user:info "$uid" >/dev/null 2>&1; then
    echo "Nextcloud user zaten var: $uid"
  else
    if OC_PASS="$pass" occ user:add --password-from-env --display-name="$display" "$uid" >/dev/null 2>&1; then
      echo "Nextcloud user olusturuldu: $uid"
    elif OC_PASS="$pass" occ user:add --password-from-env "$uid" >/dev/null 2>&1; then
      echo "Nextcloud user olusturuldu: $uid"
    else
      echo "Uyari: Nextcloud user olusturulamadi, devam ediliyor: $uid"
      return 0
    fi
  fi
  occ user:setting "$uid" settings email "${uid}@bacmastercloud.com" >/dev/null 2>&1 || true
  occ user:setting "$uid" core lang tr >/dev/null 2>&1 || true
  occ user:setting "$uid" files quota "$quota" >/dev/null 2>&1 || true
  occ user:profile "$uid" displayname "$display" >/dev/null 2>&1 || true
  docker exec -u www-data hb-nextcloud php /tmp/homelab-set-nextcloud-display.php "$uid" "$display" >/dev/null 2>&1 || true
}

apply_avatar() {
  local uid="$1" url="$2" tmp="/tmp/homelab-nextcloud-avatar-${uid}.img"
  [[ -n "$uid" && -n "$url" ]] || return 0
  if ! curl -fsSL "$url" -o "$tmp"; then
    echo "Nextcloud avatar indirilemedi: $uid -> $url"
    return 0
  fi
  docker cp "$tmp" "hb-nextcloud:/tmp/${uid}-avatar.img" >/dev/null || {
    echo "Nextcloud avatar container'a kopyalanamadi: $uid"
    return 0
  }
  docker exec -u www-data hb-nextcloud php /tmp/homelab-set-nextcloud-avatar.php "$uid" "/tmp/${uid}-avatar.img" >/dev/null || {
    echo "Nextcloud avatar uygulanamadi: $uid"
    return 0
  }
  echo "Nextcloud avatar uygulandi: $uid"
}

ensure_user "${BACMASTER_USER:-bacmaster}" "Bacmaster" "${BACMASTER_PASS:-}"
ensure_user "${ATLON_USER:-atlon}" "Atlon" "${ATLON_PASS:-}"
ensure_user "${ELIFEZEL_USER:-elifezel}" "Elifezel" "${ELIFEZEL_PASS:-}"
ensure_user "${TULUMBA_USER:-tulumba}" "Tulumba" "${TULUMBA_PASS:-}"

apply_avatar "${BACMASTER_USER:-bacmaster}" "${BACMASTER_AVATAR_URL:-}"
apply_avatar "${ATLON_USER:-atlon}" "${ATLON_AVATAR_URL:-}"
apply_avatar "${ELIFEZEL_USER:-elifezel}" "${ELIFEZEL_AVATAR_URL:-}"
apply_avatar "${TULUMBA_USER:-tulumba}" "${TULUMBA_AVATAR_URL:-}"

occ maintenance:repair >/dev/null 2>&1 || true
echo "Nextcloud/Bacscloud profilleri hazir: $brand"
REMOTE

password_rscp "$TMP/nextcloud-profiles.env" 104 /tmp/homelab-nextcloud-profiles.env
password_rscp "$TMP/apply-nextcloud-profiles.remote.sh" 104 /tmp/apply-nextcloud-profiles.remote.sh
password_sudo_bash 104 "set -a; source /tmp/homelab-nextcloud-profiles.env; set +a; bash /tmp/apply-nextcloud-profiles.remote.sh"
