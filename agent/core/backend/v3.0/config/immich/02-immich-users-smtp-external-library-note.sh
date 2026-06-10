#!/usr/bin/env bash
set -Eeuo pipefail
set +H

echo
echo "📸 Homelab v2.4.7 - Immich Configurator"
echo

source /root/homelab-secrets/users.env

VM106_IP="192.168.50.106"
SSH_USER="${BACMASTER_USER:-bacmaster}"
SSH_PASS="${BACMASTER_PASS:?BACMASTER_PASS yok}"

IMMICH_URL="http://192.168.50.106:2283"

ADMIN_EMAIL="admin@bacmastercloud.com"
ADMIN_NAME="bacmaster"
ADMIN_PASS="${BACMASTER_PASS}"

PERSONAL_EMAIL="cinarburhan1601@gmail.com"
PERSONAL_NAME="Burhan Cinar"
PERSONAL_PASS="${BACMASTER_PASS}"

TRUENAS_IP="192.168.50.101"
TANK_NFS="${TRUENAS_IP}:/mnt/tank/photos"
PRIVATE_NFS="${TRUENAS_IP}:/mnt/tank/private/photos"

TANK_MOUNT="/mnt/tank/photos"
PRIVATE_MOUNT="/mnt/private/photos"

apt update
apt install -y sshpass curl jq

shell_quote(){ printf "%q" "$1"; }

TMP="$(mktemp)"

cat > "$TMP" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
set +H

AI_DIR="/opt/homelab/immich"
cd "$AI_DIR"

echo
echo "📦 Paketler kontrol ediliyor..."
apt update >/dev/null
apt install -y curl jq nfs-common python3 >/dev/null

echo
echo "📁 TrueNAS photo mount klasörleri hazırlanıyor..."
mkdir -p "$TANK_MOUNT" "$PRIVATE_MOUNT"

ensure_fstab() {
  local src="$1"
  local dst="$2"

  if ! grep -qs "$dst" /etc/fstab; then
    echo "$src $dst nfs defaults,_netdev,x-systemd.automount,nofail 0 0" >> /etc/fstab
    echo "✅ fstab eklendi: $src -> $dst"
  else
    echo "✅ fstab zaten var: $dst"
  fi
}

ensure_fstab "$TANK_NFS" "$TANK_MOUNT"
ensure_fstab "$PRIVATE_NFS" "$PRIVATE_MOUNT"

systemctl daemon-reload
mount "$TANK_MOUNT" 2>/dev/null || true
mount "$PRIVATE_MOUNT" 2>/dev/null || true

echo
echo "🧪 Mount kontrol..."
if mountpoint -q "$TANK_MOUNT"; then
  echo "✅ tank photos mount OK: $TANK_MOUNT"
else
  echo "❌ tank photos mount olmadı: $TANK_MOUNT"
  exit 1
fi

if mountpoint -q "$PRIVATE_MOUNT"; then
  echo "✅ private photos mount OK: $PRIVATE_MOUNT"
else
  echo "❌ private photos mount olmadı: $PRIVATE_MOUNT"
  exit 1
fi

mkdir -p "$TANK_MOUNT/immich-upload" "$PRIVATE_MOUNT"
chown -R 1000:1000 "$TANK_MOUNT/immich-upload" 2>/dev/null || true

echo
echo "🧩 docker-compose.yml Immich mountları garantiye alınıyor..."

python3 - <<PY
from pathlib import Path

p = Path("docker-compose.yml")
text = p.read_text()

# Immich server'a host path'leri eklemeye çalışır.
# Duplicate olmasın diye önce yoksa ekliyoruz.
mounts = [
    "      - /mnt/tank/photos:/mnt/tank/photos:rw",
    "      - /mnt/private/photos:/mnt/private/photos:ro",
]

if "immich-server:" in text:
    lines = text.splitlines()
    out = []
    in_server = False
    in_volumes = False
    inserted = False

    for i, line in enumerate(lines):
        if line.startswith("  immich-server:") or line.strip() == "immich-server:":
            in_server = True
            inserted = False
        elif in_server and line.startswith("  ") and line.strip().endswith(":") and "immich-server:" not in line:
            if not inserted:
                # volumes bloğu hiç yakalanmadıysa environment öncesine eklenemez; pas geçeriz
                pass
            in_server = False

        out.append(line)

        if in_server and line.strip() == "volumes:":
            in_volumes = True
            continue

        if in_server and in_volumes:
            next_is_non_volume = False
            if i + 1 < len(lines):
                nxt = lines[i+1]
                if nxt.startswith("    ") and not nxt.startswith("      -"):
                    next_is_non_volume = True
            if next_is_non_volume and not inserted:
                existing = "\n".join(out)
                for m in mounts:
                    if m not in existing:
                        out.append(m)
                inserted = True
                in_volumes = False

    new = "\n".join(out) + "\n"
    p.write_text(new)
PY

docker compose config >/dev/null

echo
echo "🚀 Immich containerları başlatılıyor..."
docker compose up -d database redis immich-machine-learning immich-server || docker compose up -d

echo
echo "⏳ Immich API bekleniyor..."
for i in {1..120}; do
  CODE="$(curl -sS -o /tmp/immich-health.txt -w "%{http_code}" http://127.0.0.1:2283/api/server/ping || true)"
  if [[ "$CODE" == "200" || "$CODE" == "201" ]]; then
    echo "✅ Immich API hazır."
    break
  fi
  sleep 2
done

echo
echo "📋 Immich container durumu:"
docker compose ps | grep -Ei 'immich|redis|postgres|db' || true

echo
echo "🔐 Admin login deneniyor..."

login() {
  local email="$1"
  local pass="$2"

  curl -sS -X POST "http://127.0.0.1:2283/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$email\",\"password\":\"$pass\"}"
}

LOGIN_JSON="$(login "$ADMIN_EMAIL" "$ADMIN_PASS" || true)"
TOKEN="$(echo "$LOGIN_JSON" | jq -r '.accessToken // .access_token // empty' 2>/dev/null || true)"

if [[ -z "$TOKEN" ]]; then
  echo "👑 Admin yok gibi; admin signup deneniyor..."

  curl -sS -X POST "http://127.0.0.1:2283/api/auth/admin-sign-up" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASS\",\"name\":\"$ADMIN_NAME\"}" >/tmp/immich-admin-signup.json || true

  cat /tmp/immich-admin-signup.json || true
  echo

  LOGIN_JSON="$(login "$ADMIN_EMAIL" "$ADMIN_PASS" || true)"
  TOKEN="$(echo "$LOGIN_JSON" | jq -r '.accessToken // .access_token // empty' 2>/dev/null || true)"
fi

if [[ -z "$TOKEN" ]]; then
  echo "❌ Admin login alınamadı."
  echo "$LOGIN_JSON"
  docker logs hb-immich-server --tail=120 || true
  exit 1
fi

echo "✅ Admin token alındı."

api() {
  local method="$1"
  local path="$2"
  local data="${3:-}"

  if [[ -n "$data" ]]; then
    curl -sS -X "$method" "http://127.0.0.1:2283$path" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d "$data"
  else
    curl -sS -X "$method" "http://127.0.0.1:2283$path" \
      -H "Authorization: Bearer $TOKEN"
  fi
}

echo
echo "👤 Şahsi kullanıcı oluşturuluyor/güncelleniyor..."

USERS_JSON="$(api GET /api/admin/users || api GET /api/users || true)"
PERSONAL_ID="$(echo "$USERS_JSON" | jq -r --arg email "$PERSONAL_EMAIL" '.[]? | select(.email==$email) | .id' 2>/dev/null | head -n1 || true)"

if [[ -z "$PERSONAL_ID" ]]; then
  CREATE_USER_BODY="$(jq -n \
    --arg email "$PERSONAL_EMAIL" \
    --arg password "$PERSONAL_PASS" \
    --arg name "$PERSONAL_NAME" \
    '{email:$email,password:$password,name:$name,shouldChangePassword:false,isAdmin:false}')"

  CREATE_USER="$(api POST /api/admin/users "$CREATE_USER_BODY" || true)"
  echo "$CREATE_USER" | jq . || echo "$CREATE_USER"

  USERS_JSON="$(api GET /api/admin/users || api GET /api/users || true)"
  PERSONAL_ID="$(echo "$USERS_JSON" | jq -r --arg email "$PERSONAL_EMAIL" '.[]? | select(.email==$email) | .id' 2>/dev/null | head -n1 || true)"
fi

if [[ -n "$PERSONAL_ID" ]]; then
  echo "✅ Şahsi kullanıcı hazır: $PERSONAL_EMAIL / $PERSONAL_ID"
else
  echo "⚠️ Şahsi kullanıcı API ile doğrulanamadı. UI’dan kontrol et."
fi

echo
echo "📚 External library ayarları deneniyor..."

ADMIN_ID="$(echo "$USERS_JSON" | jq -r --arg email "$ADMIN_EMAIL" '.[]? | select(.email==$email) | .id' 2>/dev/null | head -n1 || true)"

create_library() {
  local owner_id="$1"
  local name="$2"
  local path="$3"

  [[ -z "$owner_id" ]] && return 0

  BODY="$(jq -n \
    --arg ownerId "$owner_id" \
    --arg name "$name" \
    --arg path "$path" \
    '{ownerId:$ownerId,name:$name,importPaths:[$path],exclusionPatterns:[],type:"EXTERNAL"}')"

  echo "➡️ Library: $name -> $path"

  RESP="$(api POST /api/libraries "$BODY" || true)"
  echo "$RESP" | jq . || echo "$RESP"
}

if [[ -n "$ADMIN_ID" ]]; then
  create_library "$ADMIN_ID" "Tank Photos" "/mnt/tank/photos"
fi

if [[ -n "$PERSONAL_ID" ]]; then
  create_library "$PERSONAL_ID" "Private Photos" "/mnt/private/photos"
fi

echo
echo "🤖 Machine Learning kontrol..."
ML_STATUS="$(docker inspect -f '{{.State.Health.Status}}' hb-immich-machine-learning 2>/dev/null || echo unknown)"
echo "Immich ML container health: $ML_STATUS"

echo
echo "📋 Final:"
echo "Immich URL: http://192.168.50.106:2283"
echo "Admin: $ADMIN_EMAIL / BACMASTER_PASS"
echo "Personal: $PERSONAL_EMAIL / BACMASTER_PASS"
echo "Tank photos: $TANK_MOUNT"
echo "Private photos: $PRIVATE_MOUNT"

echo
echo "✅ Immich yapılandırması tamamlandı."
REMOTE

sshpass -p "$SSH_PASS" scp \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  "$TMP" "$SSH_USER@$VM106_IP:/tmp/configure-immich.sh" >/dev/null

sshpass -p "$SSH_PASS" ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  "$SSH_USER@$VM106_IP" \
  "printf '%s\n' $(shell_quote "$SSH_PASS") | sudo -S -p '' env \
ADMIN_EMAIL=$(shell_quote "$ADMIN_EMAIL") \
ADMIN_NAME=$(shell_quote "$ADMIN_NAME") \
ADMIN_PASS=$(shell_quote "$ADMIN_PASS") \
PERSONAL_EMAIL=$(shell_quote "$PERSONAL_EMAIL") \
PERSONAL_NAME=$(shell_quote "$PERSONAL_NAME") \
PERSONAL_PASS=$(shell_quote "$PERSONAL_PASS") \
TRUENAS_IP=$(shell_quote "$TRUENAS_IP") \
TANK_NFS=$(shell_quote "$TANK_NFS") \
PRIVATE_NFS=$(shell_quote "$PRIVATE_NFS") \
TANK_MOUNT=$(shell_quote "$TANK_MOUNT") \
PRIVATE_MOUNT=$(shell_quote "$PRIVATE_MOUNT") \
bash /tmp/configure-immich.sh"

rm -f "$TMP"

echo
echo "✅ config/immich/02-immich-users-smtp-external-library-note.sh tamamlandı."
echo "Kontrol: http://192.168.50.106:2283"
