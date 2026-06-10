#!/usr/bin/env bash
set -euo pipefail

export TERM=xterm

SECRETS_DIR="${SECRETS_DIR:-/root/homelab-secrets}"
USERS_ENV="$SECRETS_DIR/users.env"
TRUENAS_API_ENV="$SECRETS_DIR/truenas-api.env"
FRESH_API_MARKER="$SECRETS_DIR/.fresh-truenas-api-required"

TRUENAS_IP_DEFAULT="192.168.50.101"
NEXTCLOUD_UID="33"
NEXTCLOUD_GID="33"
TRUENAS_PRIVATE_REQUIRED="${TRUENAS_PRIVATE_REQUIRED:-0}"

private_required() {
  case "${TRUENAS_PRIVATE_REQUIRED:-0}" in
    1|true|True|TRUE|yes|Yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

echo
echo "🧊 Homelab v2.4.7 - TrueNAS users + datasets + NFS + SMB"
echo

[[ -f "$USERS_ENV" ]] || {
  echo "❌ $USERS_ENV yok. Önce Install Menu -> 1) Bootstrap secrets/env çalıştır."
  exit 1
}

set -a
source "$USERS_ENV"
set +a

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

if [[ -f "$FRESH_API_MARKER" ]]; then
  cat <<MSG
❌ Fresh TrueNAS API key henüz yeniden üretilmemiş görünüyor:
  $FRESH_API_MARKER

Bu aşama import edilmiş/eski truenas-api.env dosyasına güvenmez.
Önce Install Menu -> 4 veya guided pipeline Phase C post-install helper ile yeni API key üretmeli.
MSG
  exit 1
fi

if [[ -f "$TRUENAS_API_ENV" ]]; then
  echo "✅ TrueNAS API env bulundu: $TRUENAS_API_ENV"
  set -a
  # shellcheck disable=SC1090
  source "$TRUENAS_API_ENV"
  set +a
  TRUENAS_IP="${TRUENAS_HOST:-${TRUENAS_IP:-$TRUENAS_IP_DEFAULT}}"
else
  cat <<MSG
❌ TrueNAS API env bulunamadı:
  $TRUENAS_API_ENV

Önce şu akışı tamamla:
  1) TrueNAS manuel kurulumunu bitir
  2) TrueNAS WebUI > Services > SSH aç
  3) Install Menu -> 4 seçeneğini çalıştır; post-install helper YENİ truenas-api.env dosyasını oluşturacak

API key burada elle sorulmaz ve secrets backup içinden import edilmez.
MSG
  exit 1
fi

: "${TRUENAS_API_KEY:?TRUENAS_API_KEY eksik. $TRUENAS_API_ENV dosyasını kontrol et.}"

TN_API="http://${TRUENAS_IP}/api/v2.0"

tn_get() {
  curl -sk --connect-timeout 10 --max-time 30 \
    -H "Authorization: Bearer ${TRUENAS_API_KEY}" \
    "$TN_API/$1"
}

tn_post() {
  curl -sk --connect-timeout 10 --max-time 30 \
    -X POST \
    -H "Authorization: Bearer ${TRUENAS_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$2" \
    "$TN_API/$1"
}

tn_put() {
  curl -sk --connect-timeout 10 --max-time 30 \
    -X PUT \
    -H "Authorization: Bearer ${TRUENAS_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$2" \
    "$TN_API/$1"
}

tn_get_json_retry() {
  local endpoint="$1"
  local outfile="$2"
  local tries="${3:-30}"
  local delay="${4:-5}"
  local code="" i=""

  for i in $(seq 1 "$tries"); do
    code="$(curl -sk --connect-timeout 10 --max-time 30       -H "Authorization: Bearer ${TRUENAS_API_KEY}"       -o "$outfile" -w "%{http_code}"       "$TN_API/$endpoint" || true)"

    if [[ "$code" =~ ^2[0-9][0-9]$ ]] && python3 -m json.tool "$outfile" >/dev/null 2>&1; then
      return 0
    fi

    echo "⏳ TrueNAS endpoint bekleniyor: $endpoint (attempt $i/$tries, HTTP ${code:-curl_failed})"
    head -c 300 "$outfile" 2>/dev/null || true
    echo
    sleep "$delay"
  done

  echo "❌ TrueNAS endpoint hazır değil veya JSON dönmüyor: $endpoint"
  echo "Son cevap:"
  cat "$outfile" 2>/dev/null || true
  return 1
}

json_has_error() {
  local file="$1"

  python3 - "$file" <<'PY'
import json, sys
from pathlib import Path

p = Path(sys.argv[1])
text = p.read_text(errors="ignore").strip()

if not text:
    sys.exit(0)

try:
    data = json.loads(text)
except Exception:
    print(text)
    sys.exit(1)

def bad(x):
    if isinstance(x, dict):
        keys = {str(k).lower() for k in x.keys()}
        if {"error", "errors", "exception", "trace", "errno", "errname"} & keys:
            return True
        if any(isinstance(v, list) for v in x.values()) and any(
            isinstance(i, dict) and "message" in i for v in x.values() if isinstance(v, list) for i in v
        ):
            return True
        return any(bad(v) for v in x.values())
    if isinstance(x, list):
        return any(bad(i) for i in x)
    return False

if bad(data):
    print(json.dumps(data, indent=2, ensure_ascii=False))
    sys.exit(1)

sys.exit(0)
PY
}

json_get_id_by_key() {
  local file="$1"
  local key="$2"
  local value="$3"

  python3 - "$file" "$key" "$value" <<'PY'
import json, sys
from pathlib import Path

file, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.loads(Path(file).read_text(errors="ignore") or "[]")

for item in data:
    if str(item.get(key, "")) == value:
        print(item.get("id", ""))
        break
PY
}

echo
echo "🔍 TrueNAS API kontrol ediliyor..."

if ! tn_get_json_retry "system/info" /tmp/truenas-info.json 30 5; then
  echo "❌ TrueNAS API erişimi başarısız."
  echo "Sıfırlamak için: rm -f $TRUENAS_API_ENV"
  exit 1
fi

if grep -qi "unauthorized\|authentication\|forbidden" /tmp/truenas-info.json; then
  echo "❌ TrueNAS API key hatalı."
  echo "Sıfırlamak için: rm -f $TRUENAS_API_ENV"
  exit 1
fi

# system/info OK can be too early right after a fresh boot. Wait for the endpoints
# this script actually needs before creating groups/users/shares.
for ep in group user pool/dataset sharing/nfs sharing/smb; do
  tn_get_json_retry "$ep" "/tmp/truenas-ready-${ep//\//-}.json" 30 5 || exit 1
done

echo "✅ TrueNAS API erişimi ve endpoint readiness tamam"

get_group_id() {
  local name="$1"

  tn_get_json_retry "group" /tmp/truenas-groups.json 30 5

  python3 - "$name" <<'PY'
import json, sys
from pathlib import Path

target = sys.argv[1]
data = json.loads(Path("/tmp/truenas-groups.json").read_text() or "[]")

for g in data:
    if g.get("group") == target or g.get("name") == target:
        print(g.get("id", ""))
        break
PY
}

get_user_id() {
  local name="$1"

  tn_get_json_retry "user" /tmp/truenas-users.json 30 5

  python3 - "$name" <<'PY'
import json, sys
from pathlib import Path

target = sys.argv[1]
data = json.loads(Path("/tmp/truenas-users.json").read_text() or "[]")

for u in data:
    if u.get("username") == target:
        print(u.get("id", ""))
        break
PY
}

ensure_group() {
  local name="$1"
  local gid="$2"

  if [[ -n "$(get_group_id "$name")" ]]; then
    echo "✅ Group mevcut: $name"
    return 0
  fi

  echo "➕ Group oluşturuluyor: $name / GID $gid"

  tn_post "group" "{
    \"name\": \"${name}\",
    \"gid\": ${gid},
    \"smb\": false
  }" >/tmp/truenas-group-create.json

  if ! json_has_error /tmp/truenas-group-create.json; then
    echo "❌ Group oluşturulamadı: $name"
    exit 1
  fi
}

ensure_user() {
  local username="$1"
  local password="$2"
  local uid="$3"
  local gid="$4"
  local full_name="$5"
  local smb="$6"

  ensure_group "$username" "$gid"

  local group_id
  group_id="$(get_group_id "$username")"

  local user_id
  user_id="$(get_user_id "$username")"

  if [[ -n "$user_id" ]]; then
    echo "✅ User mevcut: $username"

    tn_put "user/id/${user_id}" "{
      \"full_name\": \"${full_name}\",
      \"password\": \"${password}\",
      \"smb\": ${smb}
    }" >/tmp/truenas-user-update.json || true

    return 0
  fi

  echo "➕ User oluşturuluyor: $username / UID $uid / GID $gid"

  tn_post "user" "{
    \"username\": \"${username}\",
    \"full_name\": \"${full_name}\",
    \"uid\": ${uid},
    \"group\": ${group_id},
    \"password\": \"${password}\",
    \"smb\": ${smb}
  }" >/tmp/truenas-user-create.json

  if ! json_has_error /tmp/truenas-user-create.json; then
    echo "❌ User oluşturulamadı: $username"
    exit 1
  fi

  echo "✅ User oluşturuldu: $username"
}

echo
echo "👤 TrueNAS kullanıcıları hazırlanıyor..."

ensure_user "$MEDIA_USER" "$MEDIA_PASS" "$MEDIA_UID" "$MEDIA_GID" "Media User" "false"
ensure_user "$BACMASTER_USER" "$BACMASTER_PASS" "$BACMASTER_UID" "$BACMASTER_GID" "Bacmaster Admin User" "true"
ensure_user "$TULUMBA_USER" "$TULUMBA_PASS" "$TULUMBA_UID" "$TULUMBA_GID" "Tulumba Admin User" "true"

echo
echo "📦 Datasetler oluşturuluyor..."

DATASETS=(
  "tank/media"
  "tank/photos"
  "tank/temp"
  "tank/chia-db"
  "tank/ollama"
  "tank/nextcloud"
  "tank/nextcloud/data"
  "tank/private"
  "tank/private/documents"
  "tank/private/photos"
  "tank/private/timemachine"
)
if false; then
  DATASETS+=(
    "private/documents"
    "private/photos"
    "private/timemachine"
  )
elif false; then
  echo "⚠️ TRUENAS_PRIVATE_REQUIRED=0; private dataset/share otomasyonu atlanacak."
fi

for ds in "${DATASETS[@]}"
do
  echo "📁 Dataset: $ds"
  tn_post "pool/dataset" "{
    \"name\": \"${ds}\",
    \"share_type\": \"GENERIC\"
  }" >/tmp/truenas-dataset-create.json || true
done

echo
echo "📁 Media alt klasörleri oluşturuluyor..."

for folder in \
  "/mnt/tank/media/downloads" \
  "/mnt/tank/media/downloads/torrents" \
  "/mnt/tank/media/downloads/usenet" \
  "/mnt/tank/media/downloads/sonarr" \
  "/mnt/tank/media/downloads/radarr" \
  "/mnt/tank/media/movies" \
  "/mnt/tank/media/series" \
  "/mnt/tank/media/music" \
  "/mnt/tank/photos/immich-upload" \
  "/mnt/tank/chia-db" \
  "/mnt/tank/ollama" \
  "/mnt/tank/ollama/models" \
  "/mnt/tank/nextcloud/data" \
  "/mnt/tank/private/photos" \
  "/mnt/tank/private/documents" \
  "/mnt/tank/private/timemachine"
do
  echo "📂 $folder"
  tn_post "filesystem/mkdir" "{\"path\":\"${folder}\"}" >/dev/null || true
done

set_owner_perm() {
  local path="$1"
  local uid="$2"
  local gid="$3"
  local mode="$4"

  echo "🔐 $path => UID:$uid GID:$gid MODE:$mode"

  tn_post "filesystem/chown" "{
    \"path\": \"${path}\",
    \"uid\": ${uid},
    \"gid\": ${gid},
    \"options\": {
      \"recursive\": true,
      \"traverse\": true
    }
  }" >/dev/null || true

  tn_post "filesystem/setperm" "{
    \"path\": \"${path}\",
    \"mode\": \"${mode}\",
    \"uid\": ${uid},
    \"gid\": ${gid},
    \"options\": {
      \"recursive\": true,
      \"traverse\": true
    }
  }" >/dev/null || true
}

echo
echo "🔐 Permission ayarlanıyor..."

set_owner_perm "/mnt/tank/media" "$MEDIA_UID" "$MEDIA_GID" "775"
set_owner_perm "/mnt/tank/photos" "$MEDIA_UID" "$MEDIA_GID" "775"
set_owner_perm "/mnt/tank/photos/immich-upload" "$MEDIA_UID" "$MEDIA_GID" "775"
set_owner_perm "/mnt/tank/chia-db" "$MEDIA_UID" "$MEDIA_GID" "775"
set_owner_perm "/mnt/tank/ollama" "$MEDIA_UID" "$MEDIA_GID" "775"

# Nextcloud official container runs as www-data (UID/GID 33) and its entrypoint
# must be able to chown/write /var/www/html/data during first initialization.
# Keep this dataset/share compatible with www-data before VM104 starts Nextcloud.
set_owner_perm "/mnt/tank/nextcloud" "$NEXTCLOUD_UID" "$NEXTCLOUD_GID" "775"
set_owner_perm "/mnt/tank/nextcloud/data" "$NEXTCLOUD_UID" "$NEXTCLOUD_GID" "750"

if true; then
  set_owner_perm "/mnt/tank/private/photos" "$BACMASTER_UID" "$MEDIA_GID" "775"
  set_owner_perm "/mnt/tank/private/documents" "$BACMASTER_UID" "$BACMASTER_GID" "770"
  set_owner_perm "/mnt/tank/private/timemachine" "$BACMASTER_UID" "$BACMASTER_GID" "770"
else
  echo "⚠️ tank-only mode: private permission ayarlari atlandi."
fi

echo
echo "🔧 NFS servisi aktif ediliyor..."

tn_put "service/id/nfs" "{\"enable\":true}" >/dev/null || true
tn_post "service/start" "{\"service\":\"nfs\"}" >/dev/null || true

create_or_update_nfs_share() {
  local share_path="$1"
  local comment="$2"
  local map_user="$3"
  local map_group="$4"

  echo "📡 NFS share: $share_path"

  tn_get_json_retry "sharing/nfs" /tmp/truenas-nfs.json 30 5 || echo "[]" >/tmp/truenas-nfs.json

  local existing_id
  existing_id="$(python3 - "$share_path" <<'PY'
import json, sys
from pathlib import Path

target = sys.argv[1]
data = json.loads(Path("/tmp/truenas-nfs.json").read_text() or "[]")

for item in data:
    path = item.get("path")
    paths = item.get("paths") or []
    if target == path or target in paths:
        print(item.get("id", ""))
        break
PY
)"

  local payload
  payload="{
    \"path\": \"${share_path}\",
    \"comment\": \"${comment}\",
    \"enabled\": true,
    \"networks\": [\"192.168.50.0/24\"],
    \"mapall_user\": \"${map_user}\",
    \"mapall_group\": \"${map_group}\",
    \"ro\": false
  }"

  if [[ -n "$existing_id" ]]; then
    tn_put "sharing/nfs/id/${existing_id}" "$payload" >/tmp/nfs-update.json
    if ! json_has_error /tmp/nfs-update.json; then
      echo "❌ NFS update başarısız: $share_path"
      exit 1
    fi
  else
    tn_post "sharing/nfs" "$payload" >/tmp/nfs-create.json
    if ! json_has_error /tmp/nfs-create.json; then
      echo "❌ NFS create başarısız: $share_path"
      exit 1
    fi
  fi
}

create_or_update_nfs_share_root_map() {
  local share_path="$1"
  local comment="$2"

  echo "📡 NFS share: $share_path (mapall=root/root, Nextcloud-compatible chown)"

  tn_get_json_retry "sharing/nfs" /tmp/truenas-nfs.json 30 5 || echo "[]" >/tmp/truenas-nfs.json

  local existing_id
  existing_id="$(python3 - "$share_path" <<'PYNFSID'
import json, sys
from pathlib import Path

target = sys.argv[1]
try:
    data = json.loads(Path("/tmp/truenas-nfs.json").read_text() or "[]")
except Exception:
    data = []

for item in data:
    path = item.get("path")
    paths = item.get("paths") or []
    if target == path or target in paths:
        print(item.get("id", ""))
        break
PYNFSID
)"

  local existing_ok="no"
  if [[ -n "$existing_id" ]]; then
    existing_ok="$(python3 - "$share_path" <<'PYNFSOK'
import json, sys
from pathlib import Path

target = sys.argv[1]
try:
    data = json.loads(Path("/tmp/truenas-nfs.json").read_text() or "[]")
except Exception:
    data = []

ok = False
for item in data:
    path = item.get("path")
    paths = item.get("paths") or []
    if target == path or target in paths:
        networks = item.get("networks") or []
        ok = (
            item.get("enabled") is True
            and item.get("ro") is False
            and item.get("maproot_user", "") in ("", None)
            and item.get("maproot_group", "") in ("", None)
            and item.get("mapall_user") == "root"
            and item.get("mapall_group") == "root"
            and "192.168.50.0/24" in networks
        )
        break

print("yes" if ok else "no")
PYNFSOK
)"
  fi

  if [[ "$existing_ok" == "yes" ]]; then
    echo "✅ NFS share zaten uyumlu, update atlanıyor: $share_path"
    return 0
  fi

  local payload
  payload="$(python3 - "$share_path" "$comment" <<'PYPAYLOAD'
import json, sys
path, comment = sys.argv[1], sys.argv[2]
print(json.dumps({
    "path": path,
    "comment": comment,
    "enabled": True,
    "networks": ["192.168.50.0/24"],
    "hosts": [],
    "maproot_user": "",
    "maproot_group": "",
    "mapall_user": "root",
    "mapall_group": "root",
    "ro": False,
}, separators=(",", ":")))
PYPAYLOAD
)"

  if [[ -n "$existing_id" ]]; then
    tn_put "sharing/nfs/id/${existing_id}" "$payload" >/tmp/nfs-update.json || true
    if ! json_has_error /tmp/nfs-update.json; then
      echo "⚠️ NFS update API hata döndürdü, mevcut share tekrar doğrulanıyor: $share_path"
      cat /tmp/nfs-update.json || true
      tn_get "sharing/nfs" >/tmp/truenas-nfs-after-error.json || echo "[]" >/tmp/truenas-nfs-after-error.json
      if python3 - "$share_path" <<'PYNFSVERIFY'
import json, sys
from pathlib import Path

target = sys.argv[1]
try:
    data = json.loads(Path("/tmp/truenas-nfs-after-error.json").read_text() or "[]")
except Exception:
    sys.exit(1)

for item in data:
    path = item.get("path")
    paths = item.get("paths") or []
    if target == path or target in paths:
        networks = item.get("networks") or []
        if (
            item.get("enabled") is True
            and item.get("ro") is False
            and item.get("maproot_user", "") in ("", None)
            and item.get("maproot_group", "") in ("", None)
            and item.get("mapall_user") == "root"
            and item.get("mapall_group") == "root"
            and "192.168.50.0/24" in networks
        ):
            sys.exit(0)
        break
sys.exit(1)
PYNFSVERIFY
      then
        echo "✅ API hatasına rağmen mevcut NFS share uyumlu; devam ediliyor."
        return 0
      fi
      echo "❌ NFS update başarısız ve mevcut share uyumlu değil: $share_path"
      exit 1
    fi
  else
    tn_post "sharing/nfs" "$payload" >/tmp/nfs-create.json || true
    if ! json_has_error /tmp/nfs-create.json; then
      echo "❌ NFS create başarısız: $share_path"
      cat /tmp/nfs-create.json || true
      exit 1
    fi
  fi
}


create_or_update_nfs_share "/mnt/tank/media" "Docker/ARR/Jellyfin media NFS" "$MEDIA_USER" "$MEDIA_USER"
create_or_update_nfs_share "/mnt/tank/photos" "Immich main library NFS" "$MEDIA_USER" "$MEDIA_USER"
create_or_update_nfs_share "/mnt/tank/chia-db" "Chia DB cache NFS" "$MEDIA_USER" "$MEDIA_USER"
create_or_update_nfs_share "/mnt/tank/ollama" "Ollama model library NFS" "$MEDIA_USER" "$MEDIA_USER"
create_or_update_nfs_share_root_map "/mnt/tank/nextcloud" "Nextcloud user data NFS"
if true; then
  create_or_update_nfs_share "/mnt/tank/private/photos" "Immich external private photos NFS" "$MEDIA_USER" "$MEDIA_USER"
  create_or_update_nfs_share "/mnt/tank/private/documents" "Private documents Linux NFS" "$BACMASTER_USER" "$BACMASTER_USER"
else
  echo "⚠️ tank-only mode: private NFS share ayarlari atlandi."
fi

echo
echo "🔧 SMB servisi aktif ediliyor..."

tn_put "service/id/cifs" "{\"enable\":true}" >/dev/null || true
tn_post "service/start" "{\"service\":\"cifs\"}" >/dev/null || true

create_or_update_smb_share() {
  local name="$1"
  local path="$2"
  local comment="$3"

  echo "🪟 SMB share: $name => $path"

  tn_get_json_retry "sharing/smb" /tmp/truenas-smb.json 30 5 || echo "[]" >/tmp/truenas-smb.json

  local existing_id
  existing_id="$(json_get_id_by_key /tmp/truenas-smb.json name "$name")"

  local payload
  payload="{
    \"name\": \"${name}\",
    \"path\": \"${path}\",
    \"comment\": \"${comment}\",
    \"enabled\": true,
    \"browsable\": true
  }"

  if [[ -n "$existing_id" ]]; then
    tn_put "sharing/smb/id/${existing_id}" "$payload" >/tmp/smb-update.json
    if ! json_has_error /tmp/smb-update.json; then
      echo "❌ SMB update başarısız: $name"
      exit 1
    fi
  else
    tn_post "sharing/smb" "$payload" >/tmp/smb-create.json
    if ! json_has_error /tmp/smb-create.json; then
      echo "❌ SMB create başarısız: $name"
      exit 1
    fi
  fi
}

create_or_update_smb_share "tank-media" "/mnt/tank/media" "Media share for Windows access"
create_or_update_smb_share "tank-photos" "/mnt/tank/photos" "Immich main photos share"
create_or_update_smb_share "tank-chia-db" "/mnt/tank/chia-db" "Chia DB cache share"
create_or_update_smb_share "tank-ollama" "/mnt/tank/ollama" "Ollama model library share"
create_or_update_smb_share "tank-nextcloud" "/mnt/tank/nextcloud" "Nextcloud data share"
if true; then
  create_or_update_smb_share "private-documents" "/mnt/tank/private/documents" "Private documents share"
  create_or_update_smb_share "private-photos" "/mnt/tank/private/photos" "Private photos share"
  create_or_update_smb_share "private-timemachine" "/mnt/tank/private/timemachine" "macOS Time Machine backup share"
else
  echo "⚠️ tank-only mode: private SMB share ayarlari atlandi."
fi

echo
echo "🔄 Servisler restart..."

tn_post "service/restart" "{\"service\":\"nfs\"}" >/dev/null || true
tn_post "service/restart" "{\"service\":\"cifs\"}" >/dev/null || true

sleep 5

echo
echo "🔎 Share doğrulama..."

tn_get_json_retry "sharing/nfs" /tmp/truenas-nfs-final.json 30 5
tn_get_json_retry "sharing/smb" /tmp/truenas-smb-final.json 30 5

echo
echo "NFS API sonucu:"
cat /tmp/truenas-nfs-final.json | python3 -m json.tool || cat /tmp/truenas-nfs-final.json

echo
echo "SMB API sonucu:"
cat /tmp/truenas-smb-final.json | python3 -m json.tool || cat /tmp/truenas-smb-final.json

echo
echo "✅ TrueNAS users/datasets/NFS/SMB tamamlandı."
echo
echo "NFS:"
echo "- /mnt/tank/media"
echo "- /mnt/tank/photos"
echo "- /mnt/tank/chia-db"
echo "- /mnt/tank/ollama"
echo "- /mnt/tank/nextcloud"
if true; then
  echo "- /mnt/tank/private/photos"
  echo "- /mnt/tank/private/documents"
else
  echo "- private NFS shares skipped (TRUENAS_PRIVATE_REQUIRED=0)"
fi
echo
echo "SMB:"
echo "- \\\\192.168.50.101\\tank-media"
echo "- \\\\192.168.50.101\\tank-photos"
echo "- \\\\192.168.50.101\\tank-ollama"
echo "- \\\\192.168.50.101\\private-documents"
echo "- \\\\192.168.50.101\\private-photos"
echo "- \\\\192.168.50.101\\private-timemachine"
echo
echo "Kullanıcı:"
echo "- Windows/macOS erişimi: ${BACMASTER_USER}"
echo "- Docker/NFS servisleri: ${MEDIA_USER} UID/GID ${MEDIA_UID}/${MEDIA_GID}"
echo
echo "Not:"
if true; then
  echo "- private-timemachine şu an normal SMB share olarak açılır."
  echo "- Time Machine preset gerekiyorsa TrueNAS GUI'den Apple SMB extension aktif edilip share düzenlenebilir."
else
  echo "- private pool atlandıysa sonradan disk/pool hazır olunca storage bootstrap tekrar çalıştırılabilir."
fi
echo
