#!/usr/bin/env bash
set -euo pipefail

export TERM=xterm

USERS_ENV="/root/homelab-secrets/users.env"

VM102="192.168.50.102"
VM106="192.168.50.106"

echo
echo "🔐 Homelab v2.4.7 - Service Auth Configurator"
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

echo "👤 Servis kullanıcısı: $SERVICE_USER"
echo

apt update
apt install -y sshpass curl jq

run_ssh() {
  local ip="$1"
  local tmp_local
  tmp_local="$(mktemp)"

  cat > "$tmp_local"

  sshpass -p "$SSH_PASS" scp \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$tmp_local" "$SSH_USER@$ip:/tmp/homelab-auth-run.sh" >/dev/null

  sshpass -p "$SSH_PASS" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=8 \
    "$SSH_USER@$ip" \
    "echo '$SSH_PASS' | sudo -S -p '' bash /tmp/homelab-auth-run.sh"

  rm -f "$tmp_local"
}

configure_qbittorrent_auth_vm102() {
  echo
  echo "🧲 VM102 qBittorrent auth ayarlanıyor..."

  run_ssh "$VM102" <<EOF
set -euo pipefail

SERVICE_USER="$SERVICE_USER"
SERVICE_PASS="$SERVICE_PASS"

apt update >/dev/null
apt install -y curl jq >/dev/null

cd /opt/homelab/arr

docker compose up -d qbittorrent
sleep 8

for i in {1..60}; do
  if curl -fsS http://127.0.0.1:8080 >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

TMP_PASS="\$(docker logs hb-qbittorrent 2>&1 | grep -iE 'temporary password|A temporary password' | tail -n1 | awk -F': ' '{print \$NF}' | tr -d '\r')"

if [ -z "\$TMP_PASS" ]; then
  TMP_PASS="\$(docker logs hb-qbittorrent 2>&1 | grep -oE '[A-Za-z0-9+/=]{12,}' | tail -n1 | tr -d '\r')"
fi

COOKIE_FILE="/tmp/qbittorrent.cookies"
rm -f "\$COOKIE_FILE"

login_and_update() {
  local user="\$1"
  local pass="\$2"

  local login_result
  login_result="\$(curl -fsS -i -c "\$COOKIE_FILE" \
    --data-urlencode "username=\$user" \
    --data-urlencode "password=\$pass" \
    http://127.0.0.1:8080/api/v2/auth/login || true)"

  if echo "\$login_result" | grep -qi "Ok"; then
    echo "✅ qBittorrent login başarılı: \$user"

    curl -fsS -b "\$COOKIE_FILE" \
      --data-urlencode "json={\"web_ui_username\":\"\$SERVICE_USER\",\"web_ui_password\":\"\$SERVICE_PASS\"}" \
      http://127.0.0.1:8080/api/v2/app/setPreferences >/dev/null

    echo "✅ qBittorrent kullanıcı adı/şifre ayarlandı: \$SERVICE_USER"
    return 0
  fi

  return 1
}

if [ -n "\$TMP_PASS" ]; then
  echo "🔑 Geçici qBittorrent şifresi bulundu."
  if login_and_update "admin" "\$TMP_PASS"; then
    exit 0
  fi
fi

echo "ℹ️ Geçici şifre çalışmadı. Mevcut kullanıcılar deneniyor..."

if login_and_update "\$SERVICE_USER" "\$SERVICE_PASS"; then
  exit 0
fi

if login_and_update "admin" "\$SERVICE_PASS"; then
  exit 0
fi

echo "⚠️ qBittorrent auth otomatik değiştirilemedi."
exit 0
EOF
}

configure_sonarr_radarr_auth_vm102() {
  echo
  echo "📦 VM102 Sonarr/Radarr auth ayarlanıyor..."

  run_ssh "$VM102" <<EOF
set -euo pipefail

SERVICE_USER="$SERVICE_USER"
SERVICE_PASS="$SERVICE_PASS"

update_arr_config() {
  local name="\$1"
  local config="\$2"

  if [ ! -f "\$config" ]; then
    echo "⚠️ \$name config bulunamadı: \$config"
    return 0
  fi

  echo "🔐 \$name auth ayarlanıyor..."

  python3 - "\$config" "\$SERVICE_USER" "\$SERVICE_PASS" <<'PY'
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
user = sys.argv[2]
password = sys.argv[3]

tree = ET.parse(path)
root = tree.getroot()

def set_node(name, value):
    node = root.find(name)
    if node is None:
        node = ET.SubElement(root, name)
    node.text = value

set_node("AuthenticationMethod", "Forms")
set_node("AuthenticationRequired", "Enabled")
set_node("Username", user)
set_node("Password", password)

tree.write(path, encoding="utf-8", xml_declaration=True)
PY
}

cd /opt/homelab/arr

docker compose stop sonarr radarr || true

update_arr_config "Sonarr" "/opt/homelab/arr/config/sonarr/config.xml"
update_arr_config "Radarr" "/opt/homelab/arr/config/radarr/config.xml"

docker compose up -d sonarr radarr

echo "✅ Sonarr/Radarr auth tamamlandı."
EOF
}

configure_prowlarr_auth_vm102() {
  echo
  echo "🦊 VM102 Prowlarr auth temiz kurulumla ayarlanıyor..."

  run_ssh "$VM102" <<EOF
set -euo pipefail

SERVICE_USER="$SERVICE_USER"
SERVICE_PASS="$SERVICE_PASS"

apt update >/dev/null
apt install -y curl jq python3 >/dev/null

cd /opt/homelab/arr

echo "🧹 Prowlarr config sıfırlanıyor..."

docker compose stop prowlarr || true

if [ -d /opt/homelab/arr/config/prowlarr ]; then
  mv /opt/homelab/arr/config/prowlarr "/opt/homelab/arr/config/prowlarr.backup.\$(date +%Y%m%d-%H%M%S)"
fi

mkdir -p /opt/homelab/arr/config/prowlarr

docker compose up -d prowlarr

echo "⏳ Prowlarr config.xml bekleniyor..."

for i in {1..90}; do
  if [ -f /opt/homelab/arr/config/prowlarr/config.xml ]; then
    break
  fi
  sleep 2
done

CONFIG="/opt/homelab/arr/config/prowlarr/config.xml"

if [ ! -f "\$CONFIG" ]; then
  echo "❌ Prowlarr config.xml oluşmadı."
  exit 0
fi

echo "⏳ Prowlarr web/API bekleniyor..."

for i in {1..90}; do
  if curl -fsS http://127.0.0.1:9696 >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

API_KEY="\$(python3 - "\$CONFIG" <<'PY'
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
tree = ET.parse(path)
root = tree.getroot()
node = root.find("ApiKey")
print(node.text.strip() if node is not None and node.text else "")
PY
)"

if [ -z "\$API_KEY" ]; then
  echo "❌ Prowlarr API key bulunamadı."
  exit 0
fi

echo "🔑 Prowlarr API key bulundu."

HOST_JSON="\$(curl -fsS \
  -H "X-Api-Key: \$API_KEY" \
  http://127.0.0.1:9696/api/v1/config/host || true)"

if [ -z "\$HOST_JSON" ]; then
  echo "❌ Prowlarr host config okunamadı."
  exit 0
fi

UPDATED_JSON="\$(echo "\$HOST_JSON" | jq \
  --arg user "\$SERVICE_USER" \
  --arg pass "\$SERVICE_PASS" \
  '.authenticationMethod="forms"
   | .authenticationRequired="enabled"
   | .username=\$user
   | .password=\$pass
   | .passwordConfirmation=\$pass')"

HTTP_CODE="\$(curl -sS -o /tmp/prowlarr-auth-result.json -w "%{http_code}" \
  -X PUT \
  -H "Content-Type: application/json" \
  -H "X-Api-Key: \$API_KEY" \
  --data "\$UPDATED_JSON" \
  http://127.0.0.1:9696/api/v1/config/host || true)"

if [ "\$HTTP_CODE" = "200" ] || [ "\$HTTP_CODE" = "202" ]; then
  echo "✅ Prowlarr auth API üzerinden ayarlandı."
  docker compose restart prowlarr
else
  echo "❌ Prowlarr auth ayarlanamadı. HTTP: \$HTTP_CODE"
  cat /tmp/prowlarr-auth-result.json || true
fi

exit 0
EOF
}

configure_lidarr_auth_vm106() {
  echo
  echo "🎵 VM106 Lidarr auth ayarlanıyor..."

  run_ssh "$VM106" <<EOF
set -euo pipefail

SERVICE_USER="$SERVICE_USER"
SERVICE_PASS="$SERVICE_PASS"

if [ ! -f /opt/homelab/lidarr/config/lidarr/config.xml ]; then
  echo "⚠️ Lidarr config bulunamadı."
  exit 0
fi

cd /opt/homelab/lidarr

docker compose stop lidarr || true

python3 - /opt/homelab/lidarr/config/lidarr/config.xml "\$SERVICE_USER" "\$SERVICE_PASS" <<'PY'
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
user = sys.argv[2]
password = sys.argv[3]

tree = ET.parse(path)
root = tree.getroot()

def set_node(name, value):
    node = root.find(name)
    if node is None:
        node = ET.SubElement(root, name)
    node.text = value

set_node("AuthenticationMethod", "Forms")
set_node("AuthenticationRequired", "Enabled")
set_node("Username", user)
set_node("Password", password)

tree.write(path, encoding="utf-8", xml_declaration=True)
PY

docker compose up -d lidarr

echo "✅ Lidarr auth tamamlandı."
EOF
}

print_summary() {
  echo
  echo "✅ 05-configure-service-auth.sh tamamlandı."
  echo
  echo "🔐 Ayarlanan servisler:"
  echo "  - qBittorrent → http://192.168.50.102:8080"
  echo "  - Sonarr      → http://192.168.50.102:8989"
  echo "  - Radarr      → http://192.168.50.102:7878"
  echo "  - Prowlarr    → http://192.168.50.102:9696"
  echo "  - Lidarr      → http://192.168.50.106:8686"
  echo
  echo "👤 Kullanıcı: $SERVICE_USER"
  echo "🔑 Şifre: /root/homelab-secrets/users.env içindeki BACMASTER_PASS"
}

configure_qbittorrent_auth_vm102
configure_sonarr_radarr_auth_vm102
configure_prowlarr_auth_vm102
configure_lidarr_auth_vm106
print_summary