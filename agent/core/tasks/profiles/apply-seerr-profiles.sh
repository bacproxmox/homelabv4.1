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
  write_env_line SEERR_BRAND "${SEERR_BRAND:-Bacneyplus}"
  write_env_line SEERR_EMAIL_DOMAIN "${SEERR_EMAIL_DOMAIN:-bacneyplus.local}"
  write_env_line BACMASTER_AVATAR_URL "${BACMASTER_AVATAR_URL:-}"
  write_env_line ATLON_AVATAR_URL "${ATLON_AVATAR_URL:-}"
  write_env_line ELIFEZEL_AVATAR_URL "${ELIFEZEL_AVATAR_URL:-}"
  write_env_line TULUMBA_AVATAR_URL "${TULUMBA_AVATAR_URL:-}"
} > "$TMP/seerr-profiles.env"

cat > "$TMP/apply-seerr-profiles.remote.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail

SEERR_PATH="/opt/homelab/seerr"
cd "$SEERR_PATH" || { echo "$SEERR_PATH yok"; exit 1; }

if ! python3 - <<'PY' >/dev/null 2>&1
import bcrypt
PY
then
  apt-get update >/dev/null
  apt-get install -y python3-bcrypt sqlite3 >/dev/null
fi

DB_FILE=""
for db in "$SEERR_PATH/config/db/db.sqlite3" "$SEERR_PATH/config/db/db.sqlite" "$SEERR_PATH/config/db.sqlite3"; do
  [[ -f "$db" ]] && { DB_FILE="$db"; break; }
done
[[ -n "$DB_FILE" ]] || { echo "Seerr DB bulunamadi"; exit 1; }

docker compose stop seerr >/dev/null || true

export DB_FILE
python3 <<'PY'
import json
import os
import sqlite3
from datetime import datetime
import bcrypt

db_file = os.environ["DB_FILE"]
brand = os.environ.get("SEERR_BRAND", "Bacneyplus")
domain = os.environ.get("SEERR_EMAIL_DOMAIN", "bacneyplus.local")
settings_file = "/opt/homelab/seerr/config/settings.json"
now = datetime.utcnow().isoformat(timespec="milliseconds") + "Z"

if os.path.exists(settings_file):
    with open(settings_file, "r", encoding="utf-8") as f:
        settings = json.load(f)
else:
    settings = {}
settings.setdefault("main", {})
settings["main"]["applicationTitle"] = brand
with open(settings_file, "w", encoding="utf-8") as f:
    json.dump(settings, f, ensure_ascii=False, indent=2)

profiles = [
    {
        "uid": os.environ.get("BACMASTER_USER", "bacmaster"),
        "display": "Bacmaster",
        "password": os.environ.get("BACMASTER_PASS", ""),
        "avatar": os.environ.get("BACMASTER_AVATAR_URL", ""),
        "permissions": 1048575,
        "userType": 2,
        "isAdmin": 1,
    },
    {
        "uid": os.environ.get("ATLON_USER", "atlon"),
        "display": "Atlon",
        "password": os.environ.get("ATLON_PASS", ""),
        "avatar": os.environ.get("ATLON_AVATAR_URL", ""),
        "permissions": 32,
        "userType": 1,
        "isAdmin": 0,
    },
    {
        "uid": os.environ.get("ELIFEZEL_USER", "elifezel"),
        "display": "Elifezel",
        "password": os.environ.get("ELIFEZEL_PASS", ""),
        "avatar": os.environ.get("ELIFEZEL_AVATAR_URL", ""),
        "permissions": 32,
        "userType": 1,
        "isAdmin": 0,
    },
    {
        "uid": os.environ.get("TULUMBA_USER", "tulumba"),
        "display": "Tulumba",
        "password": os.environ.get("TULUMBA_PASS", ""),
        "avatar": os.environ.get("TULUMBA_AVATAR_URL", ""),
        "permissions": 32,
        "userType": 1,
        "isAdmin": 0,
    },
]

conn = sqlite3.connect(db_file)
conn.row_factory = sqlite3.Row
cur = conn.cursor()
cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
tables = [r["name"] for r in cur.fetchall()]
user_table = "user" if "user" in tables else "users" if "users" in tables else None
if not user_table:
    raise SystemExit("Seerr user/users tablosu yok")

cur.execute(f'PRAGMA table_info("{user_table}")')
cols = [r["name"] for r in cur.fetchall()]

def row_id_column():
    for candidate in ("id", "userId"):
        if candidate in cols:
            return candidate
    return None

id_col = row_id_column()

def put(data, key, value):
    if key in cols:
        data[key] = value

def upsert(profile):
    uid = profile["uid"]
    password = profile["password"]
    if not uid or not password:
        return
    email = f"{uid}@{domain}"
    password_hash = bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()
    where = []
    params = []
    if "username" in cols:
        where.append('lower(coalesce(username, ""))=lower(?)')
        params.append(uid)
    if "email" in cols:
        where.append('lower(coalesce(email, ""))=lower(?)')
        params.append(email)
    existing = None
    if where:
        cur.execute(f'SELECT * FROM "{user_table}" WHERE {" OR ".join(where)}', params)
        existing = cur.fetchone()
    data = {}
    put(data, "email", email)
    put(data, "username", uid)
    put(data, "displayName", profile["display"])
    put(data, "password", password_hash)
    put(data, "permissions", profile["permissions"])
    put(data, "userType", profile["userType"])
    put(data, "isAdmin", profile["isAdmin"])
    put(data, "avatar", profile["avatar"])
    put(data, "jellyfinUsername", profile["display"])
    put(data, "plexId", None)
    put(data, "plexToken", None)
    put(data, "updatedAt", now)
    put(data, "requestCount", 0)
    if existing and id_col:
        assignments = ", ".join([f'"{k}"=?' for k in data])
        cur.execute(
            f'UPDATE "{user_table}" SET {assignments} WHERE "{id_col}"=?',
            list(data.values()) + [existing[id_col]],
        )
    else:
        put(data, "createdAt", now)
        keys = list(data.keys())
        cur.execute(
            f'INSERT INTO "{user_table}" ({",".join(keys)}) VALUES ({",".join(["?"] * len(keys))})',
            [data[k] for k in keys],
        )
    print(f"Seerr profile ready: {uid}")

for profile in profiles:
    upsert(profile)

conn.commit()
conn.close()
PY

chown -R 1000:1000 "$SEERR_PATH/config"
docker compose up -d seerr >/dev/null
echo "Seerr/Bacneyplus profilleri hazir: ${SEERR_BRAND:-Bacneyplus}"
REMOTE

password_rscp "$TMP/seerr-profiles.env" 102 /tmp/homelab-seerr-profiles.env
password_rscp "$TMP/apply-seerr-profiles.remote.sh" 102 /tmp/apply-seerr-profiles.remote.sh
password_sudo_bash 102 "set -a; source /tmp/homelab-seerr-profiles.env; set +a; bash /tmp/apply-seerr-profiles.remote.sh"
