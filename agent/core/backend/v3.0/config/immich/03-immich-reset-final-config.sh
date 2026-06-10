#!/usr/bin/env bash
set -Eeuo pipefail
set +H

echo
echo "📸 Homelab v2.4.7 - Immich Reset + Final Configurator"
echo

source /root/homelab-secrets/users.env

VM106_IP="192.168.50.106"
SSH_USER="${BACMASTER_USER:-bacmaster}"
SSH_PASS="${BACMASTER_PASS:?BACMASTER_PASS yok}"

ADMIN_EMAIL="admin@bacmastercloud.com"
ADMIN_NAME="bacmaster"
ADMIN_PASS="$BACMASTER_PASS"

PERSONAL_EMAIL="cinarburhan1601@gmail.com"
PERSONAL_NAME="Burhan Cinar"
PERSONAL_PASS="$BACMASTER_PASS"

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
echo "📦 Paket kontrol..."
apt update >/dev/null
apt install -y nfs-common curl jq python3 >/dev/null

echo
echo "🛑 Immich durduruluyor..."
docker compose stop immich-server immich-machine-learning database redis || true
docker compose rm -f immich-server immich-machine-learning database redis || true

echo
echo "🧹 Eski Immich config/db/upload yedekleniyor..."
STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p config
for d in postgres redis model-cache config/immich-upload config/immich; do
  if [[ -e "$d" ]]; then
    mv "$d" "${d}.broken.$STAMP"
  fi
done

echo
echo "📁 TrueNAS mount hazırlanıyor..."
mkdir -p /mnt/tank/photos /mnt/private/photos

grep -qs " /mnt/tank/photos " /etc/fstab || echo "192.168.50.101:/mnt/tank/photos /mnt/tank/photos nfs defaults,_netdev,x-systemd.automount,nofail 0 0" >> /etc/fstab
grep -qs " /mnt/private/photos " /etc/fstab || echo "192.168.50.101:/mnt/tank/private/photos /mnt/private/photos nfs defaults,_netdev,x-systemd.automount,nofail 0 0" >> /etc/fstab

systemctl daemon-reload
mount /mnt/tank/photos 2>/dev/null || mount -a || true
mount /mnt/private/photos 2>/dev/null || mount -a || true

if ! mountpoint -q /mnt/tank/photos; then
  echo "❌ /mnt/tank/photos mount olmadı."
  exit 1
fi

if ! mountpoint -q /mnt/private/photos; then
  echo "❌ /mnt/private/photos mount olmadı."
  exit 1
fi

echo "✅ Mountlar hazır."

echo
echo "📦 Immich upload klasörü 18TB tank üzerine ayarlanıyor..."
mkdir -p /mnt/tank/photos/immich-upload
chown -R 1000:1000 /mnt/tank/photos/immich-upload || true

echo
echo "📝 docker-compose.yml düzeltiliyor..."
cp docker-compose.yml docker-compose.yml.bak.$STAMP

python3 - <<'PY'
from pathlib import Path

p = Path("docker-compose.yml")
text = p.read_text()

replacements = {
    "./config/immich-upload:/usr/src/app/upload": "/mnt/tank/photos/immich-upload:/usr/src/app/upload",
    "./config/immich/upload:/usr/src/app/upload": "/mnt/tank/photos/immich-upload:/usr/src/app/upload",
    "./immich-upload:/usr/src/app/upload": "/mnt/tank/photos/immich-upload:/usr/src/app/upload",
}

for old, new in replacements.items():
    text = text.replace(old, new)

# Eğer upload mount hiç yoksa immich-server volumes altına ekle
if "/usr/src/app/upload" not in text:
    lines = text.splitlines()
    out = []
    in_server = False
    added = False

    for i, line in enumerate(lines):
        out.append(line)

        if line.strip() == "immich-server:" or line.startswith("  immich-server:"):
            in_server = True

        if in_server and line.strip() == "volumes:" and not added:
            out.append("      - /mnt/tank/photos/immich-upload:/usr/src/app/upload")
            out.append("      - /mnt/tank/photos:/mnt/tank/photos:ro")
            out.append("      - /mnt/private/photos:/mnt/private/photos:ro")
            added = True

    text = "\n".join(out) + "\n"

# External library mountları yoksa eklemeye çalış
for mount in [
    "      - /mnt/tank/photos:/mnt/tank/photos:ro",
    "      - /mnt/private/photos:/mnt/private/photos:ro",
]:
    if mount not in text and "immich-server:" in text:
        text = text.replace(
            "      - /mnt/tank/photos/immich-upload:/usr/src/app/upload",
            "      - /mnt/tank/photos/immich-upload:/usr/src/app/upload\n" + mount
        )

p.write_text(text)
PY

docker compose config >/dev/null

echo
echo "🚀 Immich temiz başlatılıyor..."
docker compose up -d database redis immich-machine-learning immich-server

echo
echo "⏳ Immich API bekleniyor..."
for i in {1..120}; do
  if curl -fsS http://127.0.0.1:2283/api/server/ping >/dev/null 2>&1; then
    echo "✅ Immich API hazır."
    break
  fi
  sleep 2
done

if ! curl -fsS http://127.0.0.1:2283/api/server/ping >/dev/null 2>&1; then
  echo "❌ Immich API gelmedi."
  docker logs hb-immich-server --tail=120 || true
  exit 1
fi

login() {
  curl -sS -X POST "http://127.0.0.1:2283/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASS\"}"
}

echo
echo "👑 Admin oluşturuluyor..."
curl -sS -X POST "http://127.0.0.1:2283/api/auth/admin-sign-up" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASS\",\"name\":\"$ADMIN_NAME\"}" >/tmp/immich-admin.json || true

TOKEN="$(login | jq -r '.accessToken // empty')"

if [[ -z "$TOKEN" ]]; then
  echo "❌ Admin login başarısız."
  cat /tmp/immich-admin.json || true
  exit 1
fi

echo "✅ Admin hazır."

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
echo "👤 Şahsi kullanıcı oluşturuluyor..."
CREATE_USER_BODY="$(jq -n \
  --arg email "$PERSONAL_EMAIL" \
  --arg password "$PERSONAL_PASS" \
  --arg name "$PERSONAL_NAME" \
  '{email:$email,password:$password,name:$name,shouldChangePassword:false,isAdmin:false}')"

api POST /api/admin/users "$CREATE_USER_BODY" >/tmp/immich-user.json || true

USERS_JSON="$(api GET /api/admin/users)"
ADMIN_ID="$(echo "$USERS_JSON" | jq -r --arg email "$ADMIN_EMAIL" '.[] | select(.email==$email) | .id' | head -n1)"
PERSONAL_ID="$(echo "$USERS_JSON" | jq -r --arg email "$PERSONAL_EMAIL" '.[] | select(.email==$email) | .id' | head -n1)"

echo "✅ Admin ID: $ADMIN_ID"
echo "✅ Personal ID: $PERSONAL_ID"

echo
echo "📚 External library oluşturuluyor..."

create_library() {
  local owner_id="$1"
  local name="$2"
  local path="$3"

  BODY="$(jq -n \
    --arg ownerId "$owner_id" \
    --arg name "$name" \
    --arg path "$path" \
    '{ownerId:$ownerId,name:$name,importPaths:[$path],exclusionPatterns:["**/immich-upload/**"],type:"EXTERNAL"}')"

  api POST /api/libraries "$BODY" | jq .
}

create_library "$ADMIN_ID" "Tank Photos" "/mnt/tank/photos"
create_library "$PERSONAL_ID" "Private Photos" "/mnt/private/photos"

echo
echo "🧪 Upload disk kontrol..."
docker exec immich-server df -h /usr/src/app/upload || true

echo
echo "🧪 Container durumu:"
docker compose ps | grep -Ei "immich|redis|db" || true

echo
echo "✅ Immich reset + final config tamamlandı."
echo "URL: http://192.168.50.106:2283"
echo "Admin: $ADMIN_EMAIL / BACMASTER_PASS"
echo "Personal: $PERSONAL_EMAIL / BACMASTER_PASS"
REMOTE

sshpass -p "$SSH_PASS" scp \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  "$TMP" "$SSH_USER@$VM106_IP:/tmp/reset-configure-immich.sh" >/dev/null

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
bash /tmp/reset-configure-immich.sh"

rm -f "$TMP"

echo
echo "✅ config/immich/03-immich-reset-final-config.sh tamamlandı."
