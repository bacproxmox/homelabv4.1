#!/usr/bin/env bash
set -euo pipefail

export TERM=xterm

USERS_ENV="/root/homelab-secrets/users.env"

VM102="192.168.50.102"
VM106="192.168.50.106"

BAZARR_URL="http://192.168.50.102:6767"
JELLYFIN_URL="http://192.168.50.106:8096"
IMMICH_URL="http://192.168.50.106:2283"
LIDARR_URL="http://192.168.50.106:8686"

echo
echo "🎛️ Homelab v2.4.7 - Bazarr / Media Management Configurator"
echo

if [ ! -f "$USERS_ENV" ]; then
  echo "❌ $USERS_ENV bulunamadı."
  exit 1
fi

set -a
source "$USERS_ENV"
set +a

SSH_USER="${BACMASTER_USER:-bacmaster}"
SSH_PASS="${BACMASTER_PASS:-}"

SERVICE_USER="${BACMASTER_USER:-bacmaster}"
SERVICE_PASS="${BACMASTER_PASS:-}"

if [ -z "$SSH_PASS" ] || [ -z "$SERVICE_PASS" ]; then
  echo "❌ BACMASTER_PASS users.env içinde bulunamadı."
  exit 1
fi

apt update
apt install -y sshpass curl jq

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=8
)

run_ssh() {
  local ip="$1"
  local tmp_local
  tmp_local="$(mktemp)"

  cat > "$tmp_local"

  sshpass -p "$SSH_PASS" scp "${SSH_OPTS[@]}" \
    "$tmp_local" "$SSH_USER@$ip:/tmp/homelab-media-run.sh" >/dev/null

  sshpass -p "$SSH_PASS" ssh "${SSH_OPTS[@]}" \
    "$SSH_USER@$ip" \
    "echo '$SSH_PASS' | sudo -S -p '' bash /tmp/homelab-media-run.sh"

  rm -f "$tmp_local"
}

remote_api_key() {
  local ip="$1"
  local config="$2"

  sshpass -p "$SSH_PASS" ssh "${SSH_OPTS[@]}" "$SSH_USER@$ip" \
    "echo '$SSH_PASS' | sudo -S -p '' sh -c \"sed -n 's:.*<ApiKey>\\(.*\\)</ApiKey>.*:\\1:p' '$config' | head -n1\"" \
    2>/dev/null | tr -d '\r' || true
}

check_http() {
  local name="$1"
  local url="$2"

  echo "⏳ $name kontrol ediliyor: $url"

  for i in {1..45}; do
    if curl -fsS "$url" >/dev/null 2>&1; then
      echo "✅ $name erişilebilir."
      return 0
    fi
    sleep 2
  done

  echo "⚠️ $name erişilemedi."
  return 0
}

check_mounts_and_dirs() {
  echo
  echo "🧪 VM102 medya klasörleri kontrol ediliyor..."

  run_ssh "$VM102" <<'EOF'
set -euo pipefail

if ! mountpoint -q /mnt/media; then
  echo "⚠️ /mnt/media mount değil. mount -a deneniyor..."
  mount -a || true
fi

if ! mountpoint -q /mnt/media; then
  echo "❌ VM102 /mnt/media mount değil."
  exit 1
fi

for dir in \
  /mnt/media/downloads \
  /mnt/media/downloads/sonarr \
  /mnt/media/downloads/radarr \
  /mnt/media/downloads/lidarr \
  /mnt/media/movies \
  /mnt/media/series \
  /mnt/media/music \
  /mnt/media/photos
do
  mkdir -p "$dir"
  testfile="$dir/.homelab-write-test"
  echo "test" > "$testfile"
  rm -f "$testfile"
  echo "✅ VM102 yazılabilir: $dir"
done
EOF

  echo
  echo "🧪 VM106 medya klasörleri kontrol ediliyor..."

  run_ssh "$VM106" <<'EOF'
set -euo pipefail

if ! mountpoint -q /mnt/media; then
  echo "⚠️ /mnt/media mount değil. mount -a deneniyor..."
  mount -a || true
fi

if ! mountpoint -q /mnt/media; then
  echo "❌ VM106 /mnt/media mount değil."
  exit 1
fi

for dir in \
  /mnt/media/movies \
  /mnt/media/series \
  /mnt/media/music \
  /mnt/media/photos \
  /mnt/media/downloads
do
  mkdir -p "$dir"
  testfile="$dir/.homelab-write-test"
  echo "test" > "$testfile"
  rm -f "$testfile"
  echo "✅ VM106 yazılabilir: $dir"
done
EOF
}

configure_bazarr() {
  echo
  echo "💬 Bazarr Sonarr/Radarr bağlantıları + language profile ayarlanıyor..."

  SONARR_KEY="$(remote_api_key "$VM102" "/opt/homelab/arr/config/sonarr/config.xml")"
  RADARR_KEY="$(remote_api_key "$VM102" "/opt/homelab/arr/config/radarr/config.xml")"

  if [ -z "$SONARR_KEY" ] || [ -z "$RADARR_KEY" ]; then
    echo "❌ Sonarr/Radarr API key okunamadı."
    exit 1
  fi

  run_ssh "$VM102" <<EOF
set -euo pipefail

SONARR_KEY="$SONARR_KEY"
RADARR_KEY="$RADARR_KEY"

cd /opt/homelab/arr

docker compose up -d bazarr
sleep 8

echo "🔎 Bazarr config dosyası aranıyor..."

CONFIG_YAML=""
for f in \
  /opt/homelab/arr/config/bazarr/config/config.yaml \
  /opt/homelab/arr/config/bazarr/config/config.yml
do
  if [ -f "\$f" ]; then
    CONFIG_YAML="\$f"
    break
  fi
done

if [ -z "\$CONFIG_YAML" ]; then
  echo "❌ Bazarr config.yaml bulunamadı."
  exit 1
fi

echo "✅ Bazarr config bulundu: \$CONFIG_YAML"

docker compose stop bazarr || true

cp "\$CONFIG_YAML" "\$CONFIG_YAML.backup.\$(date +%Y%m%d-%H%M%S)"

python3 - "\$CONFIG_YAML" "\$SONARR_KEY" "\$RADARR_KEY" <<'PY'
import sys
from pathlib import Path
import yaml

path = Path(sys.argv[1])
sonarr_key = sys.argv[2]
radarr_key = sys.argv[3]

data = yaml.safe_load(path.read_text()) or {}

def ensure(section):
    if section not in data or data[section] is None:
        data[section] = {}
    return data[section]

general = ensure("general")
general["ip"] = "0.0.0.0"
general["port"] = 6767
general["base_url"] = ""
general["use_sonarr"] = True
general["use_radarr"] = True

# Bazarr auth otomasyonda güvenilir değil; iç ağda auth kapalı, dış erişim Cloudflare Access ile korunacak.
auth = ensure("auth")
auth["type"] = None

sonarr = ensure("sonarr")
sonarr["enabled"] = True
sonarr["ip"] = "192.168.50.102"
sonarr["port"] = 8989
sonarr["base_url"] = ""
sonarr["ssl"] = False
sonarr["apikey"] = sonarr_key

radarr = ensure("radarr")
radarr["enabled"] = True
radarr["ip"] = "192.168.50.102"
radarr["port"] = 7878
radarr["base_url"] = ""
radarr["ssl"] = False
radarr["apikey"] = radarr_key

path.write_text(yaml.safe_dump(data, allow_unicode=True, sort_keys=False))
print("Bazarr config.yaml güncellendi.")
PY

DB="/opt/homelab/arr/config/bazarr/db/bazarr.db"

if [ ! -f "\$DB" ]; then
  echo "❌ Bazarr DB bulunamadı: \$DB"
  docker compose up -d bazarr
  exit 1
fi

echo "🧩 Bazarr DB language profile oluşturuluyor..."

cp "\$DB" "\$DB.backup.\$(date +%Y%m%d-%H%M%S)"

python3 - "\$DB" <<'PY'
import sys
import sqlite3
import json

db = sys.argv[1]
profile_name = "Default Multi"

items = [
    {"id": 1, "language": "tr", "audio_exclude": "False", "audio_only_include": "False", "hi": "False", "forced": "False"},
    {"id": 2, "language": "en", "audio_exclude": "False", "audio_only_include": "False", "hi": "False", "forced": "False"},
    {"id": 3, "language": "de", "audio_exclude": "False", "audio_only_include": "False", "hi": "False", "forced": "False"},
    {"id": 4, "language": "mk", "audio_exclude": "False", "audio_only_include": "False", "hi": "False", "forced": "False"},
]

conn = sqlite3.connect(db)
cur = conn.cursor()

def table_exists(name):
    cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?", (name,))
    return cur.fetchone() is not None

def cols(table):
    cur.execute(f"PRAGMA table_info({table})")
    return [row[1] for row in cur.fetchall()]

if not table_exists("table_languages_profiles"):
    raise SystemExit("table_languages_profiles yok; Bazarr migration tamamlanmamış olabilir.")

columns = cols("table_languages_profiles")

# Eksik kolonları Bazarr 1.5.x beklentisine göre tamamla.
if "originalFormat" not in columns:
    cur.execute('ALTER TABLE table_languages_profiles ADD COLUMN originalFormat INTEGER')
if "tag" not in columns:
    cur.execute('ALTER TABLE table_languages_profiles ADD COLUMN tag TEXT')
if "mustContain" not in columns:
    cur.execute('ALTER TABLE table_languages_profiles ADD COLUMN mustContain TEXT')
if "mustNotContain" not in columns:
    cur.execute('ALTER TABLE table_languages_profiles ADD COLUMN mustNotContain TEXT')

columns = cols("table_languages_profiles")

cur.execute("SELECT profileId FROM table_languages_profiles WHERE name=?", (profile_name,))
row = cur.fetchone()

if row:
    profile_id = row[0]
else:
    cur.execute("SELECT COALESCE(MAX(profileId), 0) + 1 FROM table_languages_profiles")
    profile_id = cur.fetchone()[0]

payload = {
    "profileId": profile_id,
    "cutoff": 65535,
    "originalFormat": 0,
    "items": json.dumps(items),
    "name": profile_name,
    "mustContain": "[]",
    "mustNotContain": "[]",
    "tag": "[]",
}

insert_cols = [c for c in ["profileId", "cutoff", "originalFormat", "items", "name", "mustContain", "mustNotContain", "tag"] if c in columns]

if row:
    set_clause = ", ".join([f'"{c}"=?' for c in insert_cols if c != "profileId"])
    values = [payload[c] for c in insert_cols if c != "profileId"] + [profile_id]
    cur.execute(f'UPDATE table_languages_profiles SET {set_clause} WHERE profileId=?', values)
else:
    placeholders = ", ".join(["?"] * len(insert_cols))
    col_clause = ", ".join([f'"{c}"' for c in insert_cols])
    values = [payload[c] for c in insert_cols]
    cur.execute(f'INSERT INTO table_languages_profiles ({col_clause}) VALUES ({placeholders})', values)

# Mevcut içeriklere language profile ata.
for table in ["table_shows", "table_movies"]:
    if table_exists(table) and "profileId" in cols(table):
        cur.execute(f'UPDATE {table} SET profileId=? WHERE profileId IS NULL OR profileId=0', (profile_id,))

conn.commit()
conn.close()

print(f"Bazarr language profile hazır: {profile_name} ID={profile_id}")
PY

docker compose up -d bazarr

echo "⏳ Bazarr yeniden başlatılıyor..."
sleep 10

echo "✅ Bazarr config + language profile tamamlandı."
EOF
}

cleanup_bazarr_announcements() {
  echo
  echo "🧹 Bazarr announcements/notifications temizleniyor..."

  run_ssh "$VM102" <<'REMOTE_CLEAN_BAZARR'
set -euo pipefail
cd /opt/homelab/arr || exit 0
DB="/opt/homelab/arr/config/bazarr/db/bazarr.db"
CONFIG_DIR="/opt/homelab/arr/config/bazarr"

# Bazarr announcements are fetched from bazarr-binaries/announcements.json and shown as dismissible UI alerts.
# Do cleanup while Bazarr is stopped; otherwise SQLite changes can be overwritten or ignored by the running app.
docker compose stop bazarr >/dev/null 2>&1 || true
sleep 2

# Remove cached announcement payloads if Bazarr stored them on disk.
find "$CONFIG_DIR" -type f -iname '*announcement*' -print -delete 2>/dev/null || true

if [[ ! -f "$DB" ]]; then
  echo "⚠️ Bazarr DB bulunamadı, announcement DB cleanup atlandı: $DB"
  docker compose up -d bazarr >/dev/null || true
  exit 0
fi
cp "$DB" "$DB.announcement-cleanup.$(date +%Y%m%d-%H%M%S)" || true
python3 - "$DB" <<'PYBAZARR'
import sqlite3, sys, json, time
from pathlib import Path
p = Path(sys.argv[1])
conn = sqlite3.connect(p)
cur = conn.cursor()
cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
tables = [r[0] for r in cur.fetchall()]

def table_cols(t):
    cur.execute(f'PRAGMA table_info("{t}")')
    return [r[1] for r in cur.fetchall()]

for t in tables:
    tl = t.lower()
    cols = table_cols(t)
    lowcols = {c.lower(): c for c in cols}
    if 'announcement' in tl or 'notification' in tl:
        try:
            cur.execute(f'DELETE FROM "{t}"')
            print(f"✅ Temizlendi: {t}")
        except Exception as e:
            print(f"⚠️ Temizlenemedi: {t}: {e}")
    # Mark any generic UI/event rows as dismissed/read when the schema exposes such flags.
    for flag in ('read', 'isread', 'seen', 'dismissed', 'is_dismissed'):
        if flag in lowcols:
            try:
                cur.execute(f'UPDATE "{t}" SET "{lowcols[flag]}"=1')
                print(f"✅ Read/dismissed işaretlendi: {t}.{lowcols[flag]}")
            except Exception as e:
                print(f"⚠️ Flag update atlandı: {t}.{lowcols[flag]}: {e}")

# Some Bazarr builds keep key/value settings. Seed likely dismissal keys for all known announcement timestamps.
known_timestamps = [1676235999, 1700791126, 1731247748, 1769802583]
known_payload = json.dumps(known_timestamps)
for t in tables:
    cols = table_cols(t)
    lowcols = {c.lower(): c for c in cols}
    key_col = lowcols.get('key') or lowcols.get('name') or lowcols.get('setting')
    val_col = lowcols.get('value') or lowcols.get('content') or lowcols.get('data')
    if key_col and val_col:
        for key in ('dismissed_announcements', 'announcements_dismissed', 'bazarr_dismissed_announcements'):
            try:
                cur.execute(f'DELETE FROM "{t}" WHERE "{key_col}"=?', (key,))
                cur.execute(f'INSERT INTO "{t}" ("{key_col}", "{val_col}") VALUES (?, ?)', (key, known_payload))
                print(f"✅ Dismissal seed yazıldı: {t}.{key_col}={key}")
                break
            except Exception:
                pass

conn.commit()
conn.close()
print("✅ Bazarr announcement cleanup best-effort tamam.")
PYBAZARR

docker compose up -d bazarr >/dev/null || true
sleep 5
REMOTE_CLEAN_BAZARR
}

prepare_recyclarr() {
  echo
  echo "♻️ Recyclarr config template hazırlanıyor..."

  SONARR_KEY="$(remote_api_key "$VM102" "/opt/homelab/arr/config/sonarr/config.xml")"
  RADARR_KEY="$(remote_api_key "$VM102" "/opt/homelab/arr/config/radarr/config.xml")"

  run_ssh "$VM102" <<EOF
set -euo pipefail

mkdir -p /opt/homelab/recyclarr/config

cat > /opt/homelab/recyclarr/docker-compose.yml <<'YAML'
services:
  recyclarr:
    image: ghcr.io/recyclarr/recyclarr:latest
    container_name: recyclarr
    user: "1000:1000"
    environment:
      - TZ=Europe/Istanbul
    volumes:
      - ./config:/config
    restart: unless-stopped
YAML

cat > /opt/homelab/recyclarr/config/recyclarr.yml <<YAML
sonarr:
  sonarr-main:
    base_url: http://192.168.50.102:8989
    api_key: $SONARR_KEY
    quality_definition:
      type: series

radarr:
  radarr-main:
    base_url: http://192.168.50.102:7878
    api_key: $RADARR_KEY
    quality_definition:
      type: movie
YAML

cd /opt/homelab/recyclarr
docker compose pull
echo "✅ Recyclarr template hazır."
EOF
}

check_media_services() {
  echo
  echo "🔎 Medya servis kontrolleri..."

  check_http "Bazarr" "$BAZARR_URL"
  check_http "Jellyfin" "$JELLYFIN_URL"
  check_http "Immich" "$IMMICH_URL"
  check_http "Lidarr" "$LIDARR_URL"
}

print_summary() {
  echo
  echo "✅ 07-bazarr-languages-and-media-management.sh tamamlandı."
  echo
  echo "Bazarr:"
  echo "  - Auth kapalı"
  echo "  - Sonarr/Radarr bağlantısı ayarlı"
  echo "  - Language profile: Default Multi"
  echo "  - Diller: Turkish, English, German, Macedonian"
  echo
  echo "Kontrol:"
  echo "  - Bazarr:   http://192.168.50.102:6767"
  echo "  - Jellyfin: http://192.168.50.106:8096"
  echo "  - Immich:   http://192.168.50.106:2283"
  echo "  - Lidarr:   http://192.168.50.106:8686"
}

check_mounts_and_dirs
configure_bazarr
cleanup_bazarr_announcements
prepare_recyclarr
check_media_services
print_summary