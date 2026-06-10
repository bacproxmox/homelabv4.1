#!/usr/bin/env bash
set -Eeuo pipefail
set +H

export TERM=xterm

echo
echo "🎟️ Homelab v2.4.7 - Seerr Full Auto Configurator"
echo

USERS_ENV="/root/homelab-secrets/users.env"

VM102_IP="192.168.50.102"
VM106_IP="192.168.50.106"

SEERR_PATH="/opt/homelab/seerr"
ARR_PATH="/opt/homelab/arr"

SONARR_CONFIG="$ARR_PATH/config/sonarr/config.xml"
RADARR_CONFIG="$ARR_PATH/config/radarr/config.xml"

SEERR_URL_LAN="http://192.168.50.102:5055"

if [[ ! -f "$USERS_ENV" ]]; then
  echo "❌ users.env bulunamadı: $USERS_ENV"
  exit 1
fi

set -a
source "$USERS_ENV"
set +a

SSH_USER="${BACMASTER_USER:-bacmaster}"
SSH_PASS="${BACMASTER_PASS:-}"

SERVICE_USER="${BACMASTER_USER:-bacmaster}"
SERVICE_PASS="${BACMASTER_PASS:-}"
SERVICE_EMAIL="${SERVICE_USER}@bacsflix.local"

if [[ -z "$SSH_PASS" || -z "$SERVICE_PASS" ]]; then
  echo "❌ BACMASTER_PASS bulunamadı."
  exit 1
fi

apt update
apt install -y sshpass curl jq sqlite3 python3

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=10
)

shell_quote() {
  printf '%q' "$1"
}

remote_read_api_key() {
  local ip="$1"
  local config_path="$2"

  sshpass -p "$SSH_PASS" ssh "${SSH_OPTS[@]}" "$SSH_USER@$ip" \
    "printf '%s\n' $(shell_quote "$SSH_PASS") | sudo -S -p '' sh -c '
      if [ -f \"$config_path\" ]; then
        sed -n \"s:.*<ApiKey>\\(.*\\)</ApiKey>.*:\\1:p\" \"$config_path\" | head -n1
      fi
    '" 2>/dev/null | tr -d '\r' || true
}

run_ssh() {
  local ip="$1"
  local tmp_local
  local remote_cmd

  tmp_local="$(mktemp)"
  cat > "$tmp_local"

  sshpass -p "$SSH_PASS" scp "${SSH_OPTS[@]}" \
    "$tmp_local" "$SSH_USER@$ip:/tmp/homelab-seerr-full-auto.sh" >/dev/null

  remote_cmd="printf '%s\n' $(shell_quote "$SSH_PASS") | sudo -S -p '' env \
SERVICE_USER=$(shell_quote "$SERVICE_USER") \
SERVICE_PASS=$(shell_quote "$SERVICE_PASS") \
SERVICE_EMAIL=$(shell_quote "$SERVICE_EMAIL") \
SONARR_KEY=$(shell_quote "$SONARR_KEY") \
RADARR_KEY=$(shell_quote "$RADARR_KEY") \
ARR_PATH=$(shell_quote "$ARR_PATH") \
SEERR_PATH=$(shell_quote "$SEERR_PATH") \
VM106_IP=$(shell_quote "$VM106_IP") \
SEERR_URL_LAN=$(shell_quote "$SEERR_URL_LAN") \
bash /tmp/homelab-seerr-full-auto.sh"

  sshpass -p "$SSH_PASS" ssh "${SSH_OPTS[@]}" "$SSH_USER@$ip" "$remote_cmd"

  rm -f "$tmp_local"
}

echo
echo "🔑 Sonarr/Radarr API key okunuyor..."

SONARR_KEY="$(remote_read_api_key "$VM102_IP" "$SONARR_CONFIG")"
RADARR_KEY="$(remote_read_api_key "$VM102_IP" "$RADARR_CONFIG")"

if [[ -z "$SONARR_KEY" ]]; then
  echo "❌ Sonarr API key okunamadı."
  exit 1
fi

if [[ -z "$RADARR_KEY" ]]; then
  echo "❌ Radarr API key okunamadı."
  exit 1
fi

echo "✅ Sonarr API key bulundu."
echo "✅ Radarr API key bulundu."

echo
echo "🎟️ VM102 Seerr full-auto setup başlıyor..."

run_ssh "$VM102_IP" <<'EOF_REMOTE'
set -Eeuo pipefail
set +H

export DEBIAN_FRONTEND=noninteractive

JELLYFIN_HOST="$VM106_IP"
JELLYFIN_PORT="8096"

SEERR_URL_LOCAL="http://127.0.0.1:5055"

apt update >/dev/null
apt install -y curl jq sqlite3 python3 python3-bcrypt >/dev/null

cd "$SEERR_PATH"

echo
echo "🧯 Seerr temiz sıfırlanıyor..."

docker compose stop seerr >/dev/null || true

if [[ -d "$SEERR_PATH/config" ]]; then
  mv "$SEERR_PATH/config" "$SEERR_PATH/config.reset.$(date +%Y%m%d-%H%M%S)"
fi

mkdir -p "$SEERR_PATH/config"
chown -R 1000:1000 "$SEERR_PATH/config"

echo
echo "🚀 Seerr ilk DB oluşturması için başlatılıyor..."

docker compose up -d seerr >/dev/null

echo
echo "⏳ DB oluşması bekleniyor..."

DB_FILE=""

for i in {1..90}; do
  for db in \
    "$SEERR_PATH/config/db/db.sqlite3" \
    "$SEERR_PATH/config/db/db.sqlite" \
    "$SEERR_PATH/config/db.sqlite3"
  do
    if [[ -f "$db" ]]; then
      DB_FILE="$db"
      break
    fi
  done

  if [[ -n "$DB_FILE" ]]; then
    break
  fi

  sleep 2
done

if [[ -z "$DB_FILE" ]]; then
  echo "❌ Seerr DB oluşmadı."
  docker logs hb-seerr --tail=100 || true
  exit 1
fi

echo "✅ DB bulundu: $DB_FILE"

echo
echo "🎬 Jellyfin token ve library bilgileri alınıyor..."

JF_AUTH="$(curl -sS -X POST "http://$JELLYFIN_HOST:$JELLYFIN_PORT/Users/authenticatebyname" \
  -H "Content-Type: application/json" \
  -H 'X-Emby-Authorization: MediaBrowser Client="Seerr", Device="Bacsflix", DeviceId="bacsflix-auto", Version="1.0.0"' \
  --data "{\"Username\":\"$SERVICE_USER\",\"Pw\":\"$SERVICE_PASS\"}" || true)"

if ! echo "$JF_AUTH" | jq empty >/dev/null 2>&1; then
  echo "❌ Jellyfin auth JSON dönmedi. Seerr config devam etmeyecek."
  echo
  echo "Muhtemel sebep: Jellyfin wizard/admin kullanıcı henüz hazır değil."
  echo "Önce çalıştır: bash config/jellyfin/01-jellyfin-libraries-and-users.sh"
  echo
  echo "İlk 500 karakter cevap:"
  echo "$JF_AUTH" | head -c 500
  echo
  exit 1
fi

JF_TOKEN="$(echo "$JF_AUTH" | jq -r '.AccessToken // empty')"
JF_USER_ID="$(echo "$JF_AUTH" | jq -r '.User.Id // empty')"

if [[ -z "$JF_TOKEN" || "$JF_TOKEN" == "null" ]]; then
  echo "❌ Jellyfin auth başarısız."
  echo "$JF_AUTH" | jq . || true
  echo "Önce Jellyfin config/wizard tamamlanmalı."
  exit 1
fi

echo "✅ Jellyfin token alındı."

JF_INFO="$(curl -sS "http://$JELLYFIN_HOST:$JELLYFIN_PORT/System/Info/Public" || echo '{}')"
if ! echo "$JF_INFO" | jq empty >/dev/null 2>&1; then
  echo "❌ Jellyfin System/Info/Public JSON dönmedi."
  echo "$JF_INFO" | head -c 500
  echo
  exit 1
fi
JF_SERVER_ID="$(echo "$JF_INFO" | jq -r '.Id // .ServerId // empty')"

if [[ -z "$JF_SERVER_ID" ]]; then
  JF_SERVER_ID="bacsflix-jellyfin"
fi

JF_LIBS="$(curl -sS \
  "http://$JELLYFIN_HOST:$JELLYFIN_PORT/Items?Recursive=true&IncludeItemTypes=CollectionFolder" \
  -H "X-Emby-Token: $JF_TOKEN" || echo '{}')"

if ! echo "$JF_LIBS" | jq empty >/dev/null 2>&1; then
  echo "❌ Jellyfin library endpoint JSON dönmedi."
  echo "$JF_LIBS" | head -c 500
  echo
  exit 1
fi

MOVIES_ID="$(echo "$JF_LIBS" | jq -r '.Items[]? | select(.Name=="Filmler" or .Name=="Movies") | .Id' | head -n1)"
SERIES_ID="$(echo "$JF_LIBS" | jq -r '.Items[]? | select(.Name=="Diziler" or .Name=="Series" or .Name=="TV Shows") | .Id' | head -n1)"

if [[ -z "$MOVIES_ID" || -z "$SERIES_ID" ]]; then
  echo "⚠️ CollectionFolder üzerinden library bulunamadı, VirtualFolders deneniyor..."

  VF_LIBS="$(curl -sS \
    "http://$JELLYFIN_HOST:$JELLYFIN_PORT/Library/VirtualFolders" \
    -H "X-Emby-Token: $JF_TOKEN" || echo '[]')"

  if ! echo "$VF_LIBS" | jq empty >/dev/null 2>&1; then
    echo "❌ Jellyfin VirtualFolders JSON dönmedi."
    echo "$VF_LIBS" | head -c 500
    echo
    exit 1
  fi

  MOVIES_ID="$(echo "$VF_LIBS" | jq -r '.[]? | select(.Name=="Filmler" or .Name=="Movies") | (.ItemId // .Id // .Name)' | head -n1)"
  SERIES_ID="$(echo "$VF_LIBS" | jq -r '.[]? | select(.Name=="Diziler" or .Name=="Series" or .Name=="TV Shows") | (.ItemId // .Id // .Name)' | head -n1)"
fi

if [[ -z "$MOVIES_ID" ]]; then
  echo "❌ Jellyfin Filmler library bulunamadı."
  exit 1
fi

if [[ -z "$SERIES_ID" ]]; then
  echo "❌ Jellyfin Diziler library bulunamadı."
  exit 1
fi

echo "✅ Filmler library ID: $MOVIES_ID"
echo "✅ Diziler library ID: $SERIES_ID"

echo
echo "🛑 Seerr durduruluyor, settings.json + DB inject yapılacak..."

docker compose stop seerr >/dev/null || true

SETTINGS_JSON="$SEERR_PATH/config/settings.json"

echo
echo "🧬 settings.json + DB inject başlıyor..."

export DB_FILE SETTINGS_JSON JF_TOKEN JF_USER_ID JF_SERVER_ID MOVIES_ID SERIES_ID JELLYFIN_HOST JELLYFIN_PORT

python3 <<'PY'
import os
import json
import uuid
import sqlite3
from datetime import datetime
import bcrypt

db_file = os.environ["DB_FILE"]
settings_file = os.environ["SETTINGS_JSON"]

SERVICE_USER = os.environ["SERVICE_USER"]
SERVICE_PASS = os.environ["SERVICE_PASS"]
SERVICE_EMAIL = os.environ["SERVICE_EMAIL"]

JF_TOKEN = os.environ["JF_TOKEN"]
JF_USER_ID = os.environ["JF_USER_ID"]
JF_SERVER_ID = os.environ["JF_SERVER_ID"]
MOVIES_ID = os.environ["MOVIES_ID"]
SERIES_ID = os.environ["SERIES_ID"]

SONARR_KEY = os.environ["SONARR_KEY"]
RADARR_KEY = os.environ["RADARR_KEY"]

JELLYFIN_HOST = os.environ["JELLYFIN_HOST"]
JELLYFIN_PORT = int(os.environ["JELLYFIN_PORT"])

now = datetime.utcnow().isoformat(timespec="milliseconds") + "Z"

settings = {
    "clientId": str(uuid.uuid4()),
    "main": {
        "apiKey": str(uuid.uuid4()).replace("-", ""),
        "applicationTitle": "Bacsflix Requests",
        "applicationUrl": "",
        "cacheImages": False,
        "defaultPermissions": 32,
        "defaultQuotas": {"movie": {}, "tv": {}},
        "hideAvailable": False,
        "hideBlacklisted": False,
        "localLogin": True,
        "mediaServerLogin": True,
        "newPlexLogin": False,
        "discoverRegion": "",
        "streamingRegion": "TR",
        "originalLanguage": "",
        "blacklistedTags": "",
        "blacklistedTagsLimit": 50,
        "mediaServerType": 4,
        "partialRequestsEnabled": True,
        "enableSpecialEpisodes": False,
        "locale": "tr",
        "youtubeUrl": ""
    },
    "plex": {
        "name": "",
        "ip": "",
        "port": 32400,
        "useSsl": False,
        "libraries": []
    },
    "jellyfin": {
        "name": "Bacsflix",
        "ip": JELLYFIN_HOST,
        "port": JELLYFIN_PORT,
        "useSsl": False,
        "urlBase": "",
        "externalHostname": "",
        "jellyfinForgotPasswordUrl": "",
        "libraries": [
            {"id": MOVIES_ID, "name": "Filmler", "enabled": True},
            {"id": SERIES_ID, "name": "Diziler", "enabled": True}
        ],
        "serverId": JF_SERVER_ID,
        "apiKey": JF_TOKEN,
        "username": SERVICE_USER,
        "password": SERVICE_PASS
    },
    "tautulli": {},
    "radarr": [
        {
            "id": 1,
            "name": "Radarr",
            "hostname": "192.168.50.102",
            "port": 7878,
            "apiKey": RADARR_KEY,
            "useSsl": False,
            "baseUrl": "",
            "activeProfileId": 1,
            "activeProfileName": "Any",
            "activeDirectory": "/media/movies",
            "isDefault": True,
            "externalUrl": "",
            "minimumAvailability": "released",
            "tags": [],
            "enableScan": True,
            "enableAutomaticSearch": True
        }
    ],
    "sonarr": [
        {
            "id": 1,
            "name": "Sonarr",
            "hostname": "192.168.50.102",
            "port": 8989,
            "apiKey": SONARR_KEY,
            "useSsl": False,
            "baseUrl": "",
            "activeProfileId": 1,
            "activeProfileName": "Any",
            "activeDirectory": "/media/series",
            "isDefault": True,
            "externalUrl": "",
            "animeQualityProfileId": 1,
            "animeRootFolder": "/media/series",
            "animeLanguageProfileId": 1,
            "tags": [],
            "enableSeasonFolders": True,
            "enableScan": True,
            "enableAutomaticSearch": True
        }
    ],
    "public": {
        "initialized": True,
        "initializedAt": now
    },
    "notifications": {"agents": {}},
    "jobs": {
        "jellyfin-recently-added-scan": {"schedule": "0 */5 * * * *"},
        "jellyfin-full-scan": {"schedule": "0 0 3 * * *"},
        "radarr-scan": {"schedule": "0 0 4 * * *"},
        "sonarr-scan": {"schedule": "0 30 4 * * *"},
        "availability-sync": {"schedule": "0 0 5 * * *"},
        "download-sync": {"schedule": "0 * * * * *"}
    },
    "network": {
        "csrfProtection": False,
        "forceIpv4First": False,
        "trustProxy": False,
        "proxy": {
            "enabled": False,
            "hostname": "",
            "port": 8080,
            "useSsl": False,
            "user": "",
            "password": "",
            "bypassFilter": "",
            "bypassLocalAddresses": True
        }
    },
    "initialized": True
}

with open(settings_file, "w", encoding="utf-8") as f:
    json.dump(settings, f, ensure_ascii=False, indent=2)

conn = sqlite3.connect(db_file)
conn.row_factory = sqlite3.Row
cur = conn.cursor()

cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
tables = [r["name"] for r in cur.fetchall()]

if "user" in tables:
    user_table = "user"
elif "users" in tables:
    user_table = "users"
else:
    raise SystemExit("user/users tablosu yok")

cur.execute(f'PRAGMA table_info("{user_table}")')
cols = [r["name"] for r in cur.fetchall()]

password_hash = bcrypt.hashpw(SERVICE_PASS.encode(), bcrypt.gensalt()).decode()

cur.execute(
    f'DELETE FROM "{user_table}" WHERE username=? OR email=? OR email=?',
    (SERVICE_USER, SERVICE_EMAIL, SERVICE_USER)
)

data = {}

def put(k, v):
    if k in cols:
        data[k] = v

put("email", SERVICE_EMAIL)
put("username", SERVICE_USER)
put("password", password_hash)
put("permissions", 1048575)
put("userType", 2)
put("avatar", "")
put("plexId", None)
put("plexToken", None)
put("jellyfinUsername", SERVICE_USER)
put("jellyfinAuthToken", JF_TOKEN)
put("jellyfinUserId", JF_USER_ID)
put("jellyfinDeviceId", "bacsflix-auto")
put("createdAt", now)
put("updatedAt", now)
put("requestCount", 0)

keys = list(data.keys())
vals = [data[k] for k in keys]

cur.execute(
    f'INSERT INTO "{user_table}" ({",".join(keys)}) VALUES ({",".join(["?"] * len(keys))})',
    vals
)


# Seerr/Overseerr schema changes between versions; force admin-like permission fields when present.
# v2.4: update not only the inserted row, but any matching local/Jellyfin user rows
# because Seerr may create/import a second user during first login and return that one.
admin_perm = 1048575
for table in tables:
    cur.execute(f'PRAGMA table_info("{table}")')
    tcols = [r["name"] for r in cur.fetchall()]
    set_parts = []
    params = []
    for col, value in [("permissions", admin_perm), ("userType", 2), ("isAdmin", 1)]:
        if col in tcols:
            set_parts.append(f'"{col}"=?')
            params.append(value)
    if not set_parts:
        continue
    where = []
    wparams = []
    if "email" in tcols:
        where.append('"email"=?')
        wparams.append(SERVICE_EMAIL)
        where.append('"email"=?')
        wparams.append(SERVICE_USER)
    if "username" in tcols:
        where.append('"username"=?')
        wparams.append(SERVICE_USER)
    if "jellyfinUserId" in tcols and JF_USER_ID:
        where.append('"jellyfinUserId"=?')
        wparams.append(JF_USER_ID)
    if where:
        cur.execute(f'UPDATE "{table}" SET {", ".join(set_parts)} WHERE {" OR ".join(where)}', params + wparams)
conn.commit()
conn.close()

print("✅ settings.json yazıldı")
print("✅ admin user DB inject edildi")
PY

chown -R 1000:1000 "$SEERR_PATH/config"

echo
echo "🚀 Seerr tekrar başlatılıyor..."

docker compose up -d seerr >/dev/null

echo
echo "⏳ Seerr API bekleniyor..."

for i in {1..90}; do
  if curl -fsS "$SEERR_URL_LOCAL/api/v1/status" >/dev/null 2>&1; then
    echo "✅ Seerr API hazır."
    break
  fi
  sleep 2
done

echo
echo "🔐 Login testi..."

LOGIN_JSON="$(curl -sS -X POST "$SEERR_URL_LOCAL/api/v1/auth/local" \
  -H "Content-Type: application/json" \
  --data "{\"email\":\"$SERVICE_EMAIL\",\"password\":\"$SERVICE_PASS\"}" || true)"

echo "$LOGIN_JSON" | jq . || true

echo
echo "📋 Seerr status:"

curl -sS "$SEERR_URL_LOCAL/api/v1/status" | jq . || true

echo
echo "✅ Seerr full-auto yapılandırma tamamlandı."
echo
echo "Kontrol:"
echo "  $SEERR_URL_LAN"
echo
echo "Login:"
echo "  Email: $SERVICE_EMAIL"
echo "  Password: BACMASTER_PASS"

echo
echo "🔎 Admin permission doğrulanıyor..."
PERM="$(echo "$LOGIN_JSON" | jq -r '.permissions // empty' 2>/dev/null || true)"
if [[ -z "$PERM" || "$PERM" == "0" ]]; then
  echo "⚠️ Login response permissions düşük görünüyor: ${PERM:-empty}. DB permission patch uygulanmıştı; UI'da admin yetkisini doğrula."
else
  echo "✅ Admin permissions: $PERM"
fi

echo
echo "🔄 Seerr initial scan jobları tetikleniyor..."
API_KEY="$(jq -r '.main.apiKey' "$SEERR_PATH/config/settings.json")"
for job in jellyfin-full-scan jellyfin-recently-added-scan availability-sync; do
  curl -sS -X POST "$SEERR_URL_LOCAL/api/v1/settings/jobs/${job}/run" -H "X-Api-Key: $API_KEY" >/dev/null || true
  echo "✅ Job tetiklendi: $job"
done

echo
echo "✅ Seerr full-auto yapılandırma tamamlandı."
echo
echo "Kontrol:"
echo "  $SEERR_URL_LAN"
echo
echo "Login:"
echo "  Email: $SERVICE_EMAIL"
echo "  Password: BACMASTER_PASS"
EOF_REMOTE

echo
echo "✅ config/seerr/02-seerr-full-auto-config.sh tamamlandı."
echo "Kontrol: $SEERR_URL_LAN"
