#!/usr/bin/env bash
set -Eeuo pipefail
set +H

export TERM=xterm

echo
echo "🎬 Homelab v2.4.7 - Jellyfin Post-Setup Configurator"
echo

USERS_ENV="/root/homelab-secrets/users.env"
VM106_IP="192.168.50.106"

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

if [[ -z "$SSH_PASS" || -z "$SERVICE_PASS" ]]; then
  echo "❌ BACMASTER_PASS bulunamadı."
  exit 1
fi

apt update
apt install -y sshpass curl jq

# v2.4: Jellyfin viewer users use passwords collected in users.env.
# No separate random shared viewer password is generated anymore.
ATLON_PASS="${ATLON_PASS:-}"
ELIFEZEL_PASS="${ELIFEZEL_PASS:-}"
TULUMBA_PASS="${TULUMBA_PASS:-}"

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
    "$tmp_local" "$SSH_USER@$ip:/tmp/homelab-jellyfin-run.sh" >/dev/null

  sshpass -p "$SSH_PASS" ssh "${SSH_OPTS[@]}" \
    "$SSH_USER@$ip" \
    "echo '$SSH_PASS' | sudo -S -p '' bash /tmp/homelab-jellyfin-run.sh"

  rm -f "$tmp_local"
}

echo
echo "🖥️ VM106 Jellyfin yapılandırılıyor..."

run_ssh "$VM106_IP" <<EOF
set -Eeuo pipefail
set +H

SERVICE_USER="$SERVICE_USER"
SERVICE_PASS="$SERVICE_PASS"
ATLON_PASS="$ATLON_PASS"
ELIFEZEL_PASS="$ELIFEZEL_PASS"
TULUMBA_PASS="$TULUMBA_PASS"
HOMELAB_NO_JELLYFIN_WIZARD_PROMPT="${HOMELAB_NO_JELLYFIN_WIZARD_PROMPT:-0}"
HOMELAB_NO_JELLYFIN_WIZARD_GATE="${HOMELAB_NO_JELLYFIN_WIZARD_GATE:-0}"

JELLYFIN_URL="http://127.0.0.1:8096"
PUBLIC_JELLYFIN_URL="http://$VM106_IP:8096"

export DEBIAN_FRONTEND=noninteractive

apt update >/dev/null
apt install -y curl jq sqlite3 >/dev/null

if [[ ! -d /opt/homelab/jellyfin ]]; then
  echo "❌ /opt/homelab/jellyfin bulunamadı."
  echo "Muhtemel sebep: Docker media/AI stack kurulumu tamamlanmadı."
  exit 1
fi

cd /opt/homelab/jellyfin

echo
echo "🧪 /mnt/media mount ve klasör testleri..."

if ! mountpoint -q /mnt/media; then
  echo "❌ /mnt/media mount değil."
  exit 1
fi

for dir in /mnt/media/movies /mnt/media/series; do
  mkdir -p "\$dir"
  testfile="\$dir/.jellyfin-write-test"
  echo "test" > "\$testfile"
  rm -f "\$testfile"
  echo "✅ Yazılabilir: \$dir"
done

echo
echo "🎞️ Jellyfin container kontrolü..."

docker compose up -d jellyfin >/dev/null

echo
echo "⏳ Jellyfin API bekleniyor..."

JELLYFIN_READY=0

for i in {1..90}; do
  if curl -fsS "\$JELLYFIN_URL/System/Info/Public" >/dev/null 2>&1; then
    JELLYFIN_READY=1
    echo "✅ Jellyfin API hazır."
    break
  fi
  sleep 2
done

if [[ "\$JELLYFIN_READY" != "1" ]]; then
  echo "❌ Jellyfin API hazır olmadı."
  echo "Kontrol et:"
  echo "  docker ps"
  echo "  docker logs hb-jellyfin --tail=100"
  exit 1
fi

get_public_info() {
  curl -sS "\$JELLYFIN_URL/System/Info/Public" || true
}

json_or_empty() {
  local payload="\$1"
  if echo "\$payload" | jq empty >/dev/null 2>&1; then
    echo "\$payload"
  else
    echo '{}'
  fi
}

wizard_completed() {
  local info
  info="\$(get_public_info)"
  if ! echo "\$info" | jq empty >/dev/null 2>&1; then
    return 1
  fi
  [[ "\$(echo "\$info" | jq -r '.StartupWizardCompleted // false')" == "true" ]]
}

try_auto_wizard() {
  echo
  echo "🪄 Jellyfin ilk kurulum wizard otomasyonu deneniyor..."

  curl -sS -X POST "\$JELLYFIN_URL/Startup/Configuration" \
    -H "Content-Type: application/json" \
    --data '{"UICulture":"tr-TR","MetadataCountryCode":"TR","PreferredMetadataLanguage":"tr"}' >/tmp/jf-startup-config.out 2>/dev/null || true

  curl -sS "\$JELLYFIN_URL/Startup/FirstUser" >/tmp/jf-first-user.out 2>/dev/null || \
  curl -sS "\$JELLYFIN_URL/Startup/User" >/tmp/jf-first-user.out 2>/dev/null || true

  # Jellyfin sürümlerinde payload değişebildiği için birkaç güvenli varyasyon denenir.
  for payload in \
    "{\"Name\":\"\$SERVICE_USER\",\"Password\":\"\$SERVICE_PASS\"}" \
    "{\"Username\":\"\$SERVICE_USER\",\"Password\":\"\$SERVICE_PASS\"}" \
    "{\"Name\":\"\$SERVICE_USER\",\"Password\":\"\$SERVICE_PASS\",\"EnableAutoLogin\":false}"
  do
    curl -sS -X POST "\$JELLYFIN_URL/Startup/User" \
      -H "Content-Type: application/json" \
      --data "\$payload" >/tmp/jf-startup-user.out 2>/dev/null || true
    sleep 1
    if curl -sS -X POST "\$JELLYFIN_URL/Users/authenticatebyname" \
      -H "Content-Type: application/json" \
      -H 'X-Emby-Authorization: MediaBrowser Client="homelab", Device="script", DeviceId="setup", Version="1.0"' \
      --data "{\"Username\":\"\$SERVICE_USER\",\"Pw\":\"\$SERVICE_PASS\"}" | jq -e '.AccessToken' >/dev/null 2>&1; then
      break
    fi
  done

  curl -sS -X POST "\$JELLYFIN_URL/Startup/RemoteAccess" \
    -H "Content-Type: application/json" \
    --data '{"EnableRemoteAccess":true,"EnableAutomaticPortMapping":false}' >/tmp/jf-remote-access.out 2>/dev/null || true

  curl -sS -X POST "\$JELLYFIN_URL/Startup/Complete" >/tmp/jf-complete.out 2>/dev/null || true

  for i in {1..20}; do
    wizard_completed && { echo "✅ Jellyfin wizard otomatik tamamlandı."; return 0; }
    sleep 2
  done

  echo "⚠️ Jellyfin wizard otomatik tamamlanamadı. Manuel gate'e geçiliyor."
  return 1
}

PUBLIC_INFO="\$(get_public_info)"

if ! echo "\$PUBLIC_INFO" | jq empty >/dev/null 2>&1; then
  echo "❌ Jellyfin public info JSON dönmedi."
  echo "Cevap:"
  echo "\$PUBLIC_INFO" | head -c 500
  echo
  exit 1
fi

STARTUP_WIZARD_COMPLETED="\$(echo "\$PUBLIC_INFO" | jq -r '.StartupWizardCompleted // false')"

if [[ "\$STARTUP_WIZARD_COMPLETED" != "true" ]]; then
  try_auto_wizard || true
fi

if ! wizard_completed; then
  echo
  echo "⚠️ Jellyfin ilk kurulum wizard tamamlanmamış."
  echo
  echo "Tarayıcıdan aç:"
  echo "  \$PUBLIC_JELLYFIN_URL"
  echo
  echo "Admin kullanıcıyı şu bilgilerle oluştur:"
  echo "  Kullanıcı: \$SERVICE_USER"
  echo "  Şifre: users.env içindeki BACMASTER_PASS"
  echo
  if [[ "\${HOMELAB_NO_JELLYFIN_WIZARD_PROMPT:-0}" == "1" || "\${HOMELAB_NO_JELLYFIN_WIZARD_GATE:-0}" == "1" ]]; then
    echo "v3.1 guided non-interactive mod: Jellyfin wizard icin Enter beklenmeyecek."
    echo "Jellyfin hazir oldugunda core config/profil task'larini tekrar calistirabilirsin."
    exit 20
  fi
  read -r -p "Wizard tamamlandıysa Enter'a bas..." _
  if ! wizard_completed; then
    echo "❌ Wizard hâlâ tamamlanmamış. Seerr gibi bağımlı scriptlere geçilmeyecek."
    exit 20
  fi
fi

echo
echo "🔐 Jellyfin admin login deneniyor..."

AUTH_RESPONSE="\$(curl -sS -X POST "\$JELLYFIN_URL/Users/authenticatebyname" \
  -H "Content-Type: application/json" \
  -H 'X-Emby-Authorization: MediaBrowser Client="homelab", Device="script", DeviceId="setup", Version="1.0"' \
  --data "{\"Username\":\"\$SERVICE_USER\",\"Pw\":\"\$SERVICE_PASS\"}" || true)"

if [[ -z "\$AUTH_RESPONSE" ]]; then
  echo "❌ Jellyfin login boş cevap döndü."
  echo "Kontrol:"
  echo "  \$PUBLIC_JELLYFIN_URL"
  exit 1
fi

if ! echo "\$AUTH_RESPONSE" | jq empty >/dev/null 2>&1; then
  echo "❌ Jellyfin login JSON cevap dönmedi."
  echo
  echo "Muhtemel sebepler:"
  echo "  - Jellyfin wizard tamamlanmadı"
  echo "  - Admin kullanıcı adı/şifre yanlış"
  echo "  - Jellyfin endpoint HTML/text cevap döndü"
  echo
  echo "İlk 500 karakter cevap:"
  echo "\$AUTH_RESPONSE" | head -c 500
  echo
  echo "Kontrol:"
  echo "  \$PUBLIC_JELLYFIN_URL"
  exit 1
fi

ACCESS_TOKEN="\$(echo "\$AUTH_RESPONSE" | jq -r '.AccessToken // empty')"

if [[ -z "\$ACCESS_TOKEN" || "\$ACCESS_TOKEN" == "null" ]]; then
  echo "❌ Jellyfin login başarısız."
  echo
  echo "Jellyfin cevabı:"
  echo "\$AUTH_RESPONSE" | jq .
  echo
  echo "Beklenen admin:"
  echo "  \$SERVICE_USER"
  echo
  echo "Kontrol:"
  echo "  \$PUBLIC_JELLYFIN_URL"
  exit 1
fi

echo "✅ Jellyfin admin login başarılı."

AUTH_HEADER="X-Emby-Token: \$ACCESS_TOKEN"

# v2.4: Jellyfin server name should be stable and branded, not random/container-derived.
echo
echo "🏷️ Jellyfin sunucu adı Bacsflix olarak ayarlanıyor..."
SERVER_CONFIG="\$(curl -sS -H "\$AUTH_HEADER" "\$JELLYFIN_URL/System/Configuration" || echo "{}")"
if echo "\$SERVER_CONFIG" | jq empty >/dev/null 2>&1; then
  UPDATED_SERVER_CONFIG="\$(echo "\$SERVER_CONFIG" | jq '.ServerName="Bacsflix"')"
  curl -sS -X POST \
    -H "\$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    "\$JELLYFIN_URL/System/Configuration" \
    --data "\$UPDATED_SERVER_CONFIG" >/dev/null || true
  echo "✅ Jellyfin server name: Bacsflix"
else
  echo "⚠️ Jellyfin System/Configuration JSON dönmedi; server name atlandı."
fi

echo
echo "📚 Library kontrolü..."

LIBRARIES="\$(curl -sS -H "\$AUTH_HEADER" "\$JELLYFIN_URL/Library/VirtualFolders" || echo "[]")"

if echo "\$LIBRARIES" | jq empty >/dev/null 2>&1; then
  echo "\$LIBRARIES" | jq -r '.[].Name' || true
else
  echo "⚠️ Library listesi JSON dönmedi, devam ediliyor."
  LIBRARIES="[]"
fi

ensure_library() {
  local name="\$1" ctype="\$2" path="\$3"
  if echo "\$LIBRARIES" | jq -e --arg name "\$name" '.[]? | select(.Name==\$name)' >/dev/null 2>&1; then
    echo "✅ Library zaten var: \$name"
    return 0
  fi
  echo "➕ Library oluşturuluyor: \$name -> \$path"
  curl -sS -X POST     -H "\$AUTH_HEADER"     -G "\$JELLYFIN_URL/Library/VirtualFolders"     --data-urlencode "name=\$name"     --data-urlencode "collectionType=\$ctype"     --data-urlencode "paths=\$path" >/tmp/jf-library-create.out 2>/dev/null || true
  sleep 2
}

ensure_library "Filmler" "movies" "/data/movies"
ensure_library "Diziler" "tvshows" "/data/series"
LIBRARIES="\$(curl -sS -H "\$AUTH_HEADER" "\$JELLYFIN_URL/Library/VirtualFolders" || echo "[]")"

echo
echo "👥 Viewer kullanıcıları oluşturuluyor..."

VIEWERS=("Elifezel" "Atlon" "Tulumba")
VIEWER_PASSWORDS=("\$ELIFEZEL_PASS" "\$ATLON_PASS" "\$TULUMBA_PASS")
echo "ℹ️ v2.4: Orhan otomatik viewer listesinde yok. ORHAN_PASS eklenirse bile default olarak oluşturulmaz."

for idx in "\${!VIEWERS[@]}"; do
  viewer="\${VIEWERS[\$idx]}"
  viewer_pass="\${VIEWER_PASSWORDS[\$idx]}"
  if [[ -z "\$viewer_pass" ]]; then
    echo "⚠️ \$viewer için şifre boş; kullanıcı atlanıyor."
    continue
  fi
  USERS_JSON="\$(curl -sS -H "\$AUTH_HEADER" "\$JELLYFIN_URL/Users" || echo "[]")"

  if ! echo "\$USERS_JSON" | jq empty >/dev/null 2>&1; then
    echo "⚠️ Users endpoint JSON dönmedi, kullanıcı atlanıyor: \$viewer"
    continue
  fi

  EXISTING_ID="\$(echo "\$USERS_JSON" | jq -r --arg viewer "\$viewer" '.[] | select(.Name==\$viewer) | .Id' | head -n1)"

  if [[ -z "\$EXISTING_ID" ]]; then
    echo "➕ Oluşturuluyor: \$viewer"

    USER_CREATE="\$(curl -sS -X POST \
      -H "\$AUTH_HEADER" \
      -H "Content-Type: application/json" \
      "\$JELLYFIN_URL/Users/New" \
      --data "\$(jq -n --arg name "\$viewer" --arg pass "\$viewer_pass" '{Name:\$name,Password:\$pass}')" || true)"

    if echo "\$USER_CREATE" | jq empty >/dev/null 2>&1; then
      USER_ID="\$(echo "\$USER_CREATE" | jq -r '.Id // empty')"
    else
      USER_ID=""
    fi
  else
    USER_ID="\$EXISTING_ID"
    echo "ℹ️ Kullanıcı zaten var: \$viewer"
  fi

  if [[ -z "\$USER_ID" || "\$USER_ID" == "null" ]]; then
    echo "⚠️ Kullanıcı oluşturulamadı: \$viewer"
    continue
  fi

  POLICY="\$(curl -sS -H "\$AUTH_HEADER" "\$JELLYFIN_URL/Users/\$USER_ID/Policy" || echo "{}")"

  if ! echo "\$POLICY" | jq empty >/dev/null 2>&1; then
    echo "⚠️ Policy JSON dönmedi, kullanıcı atlanıyor: \$viewer"
    continue
  fi

  UPDATED_POLICY="\$(echo "\$POLICY" | jq '
    .IsAdministrator=false |
    .IsHidden=false |
    .IsHiddenRemotely=false |
    .IsDisabled=false |
    .EnableUserPreferenceAccess=true |
    .EnableRemoteControlOfOtherUsers=false |
    .EnableSharedDeviceControl=false |
    .EnableRemoteAccess=true |
    .EnableLiveTvManagement=false |
    .EnableLiveTvAccess=false |
    .EnableMediaPlayback=true |
    .EnableAudioPlaybackTranscoding=true |
    .EnableVideoPlaybackTranscoding=true |
    .EnablePlaybackRemuxing=true |
    .EnableContentDeletion=false |
    .EnableContentDeletionFromFolders=[] |
    .EnableContentDownloading=false |
    .EnableSyncTranscoding=false |
    .EnableMediaConversion=false |
    .EnableAllDevices=true |
    .EnabledDevices=[] |
    .EnableAllChannels=true |
    .EnabledChannels=[] |
    .EnableAllFolders=true |
    .EnabledFolders=[] |
    .InvalidLoginAttemptCount=0 |
    .LoginAttemptsBeforeLockout=-1
  ')"

  curl -sS -X POST \
    -H "\$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    "\$JELLYFIN_URL/Users/\$USER_ID/Policy" \
    --data "\$UPDATED_POLICY" >/dev/null

  echo "✅ Viewer hazır: \$viewer"
done

echo
echo "🌍 Admin dil/altyazı tercihleri ayarlanıyor..."

USERS_JSON="\$(curl -sS -H "\$AUTH_HEADER" "\$JELLYFIN_URL/Users" || echo "[]")"

if echo "\$USERS_JSON" | jq empty >/dev/null 2>&1; then
  ADMIN_ID="\$(echo "\$USERS_JSON" | jq -r --arg admin "\$SERVICE_USER" '.[] | select(.Name==\$admin) | .Id' | head -n1)"
else
  ADMIN_ID=""
fi

if [[ -n "\$ADMIN_ID" && "\$ADMIN_ID" != "null" ]]; then
  USER_CONFIG="\$(curl -sS -H "\$AUTH_HEADER" "\$JELLYFIN_URL/Users/\$ADMIN_ID/Configuration" || echo "{}")"

  if echo "\$USER_CONFIG" | jq empty >/dev/null 2>&1; then
    UPDATED_CONFIG="\$(echo "\$USER_CONFIG" | jq '
      .AudioLanguagePreference="tur" |
      .SubtitleLanguagePreference="tur" |
      .SubtitleMode="Default" |
      .DisplayMissingEpisodes=true |
      .EnableNextEpisodeAutoPlay=true
    ')"

    curl -sS -X POST \
      -H "\$AUTH_HEADER" \
      -H "Content-Type: application/json" \
      "\$JELLYFIN_URL/Users/\$ADMIN_ID/Configuration" \
      --data "\$UPDATED_CONFIG" >/dev/null || true

    echo "✅ Admin dil/altyazı tercihleri ayarlandı."
  else
    echo "⚠️ Admin config JSON dönmedi, atlandı."
  fi
else
  echo "⚠️ Admin ID bulunamadı, dil/altyazı tercihleri atlandı."
fi

echo
echo "⚙️ Encoding / HW acceleration ayarı kontrol ediliyor..."

HW_TYPE="none"

if [[ -d /dev/dri ]]; then
  HW_TYPE="vaapi"
elif command -v nvidia-smi >/dev/null 2>&1; then
  HW_TYPE="nvenc"
fi

ENCODING_XML="/opt/homelab/jellyfin/config/jellyfin/config/encoding.xml"
mkdir -p "\$(dirname "\$ENCODING_XML")"

if [[ ! -f "\$ENCODING_XML" ]]; then
  cat > "\$ENCODING_XML" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<EncodingOptions xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
</EncodingOptions>
XML
fi

python3 - "\$ENCODING_XML" "\$HW_TYPE" <<'PY'
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
hw = sys.argv[2]

tree = ET.parse(path)
root = tree.getroot()

def set_node(name, value):
    node = root.find(name)
    if node is None:
        node = ET.SubElement(root, name)
    node.text = value

if hw == "vaapi":
    set_node("HardwareAccelerationType", "vaapi")
    set_node("VaapiDevice", "/dev/dri/renderD128")
    set_node("EnableHardwareEncoding", "true")
elif hw == "nvenc":
    set_node("HardwareAccelerationType", "nvenc")
    set_node("EnableHardwareEncoding", "true")
else:
    set_node("HardwareAccelerationType", "none")
    set_node("EnableHardwareEncoding", "false")

tree.write(path, encoding="utf-8", xml_declaration=True)
PY

chown -R 1000:1000 /opt/homelab/jellyfin/config/jellyfin || true

echo "✅ Encoding ayarı yazıldı: \$HW_TYPE"

echo
echo "🔄 Jellyfin container restart..."

docker compose restart jellyfin >/dev/null || true
sleep 8

echo
echo "🔄 Library scan başlatılıyor..."

curl -sS -X POST \
  -H "\$AUTH_HEADER" \
  "\$JELLYFIN_URL/Library/Refresh" >/dev/null || true

echo
echo "🎉 Jellyfin yapılandırması tamamlandı."
echo
echo "📺 Jellyfin:"
echo "  URL: \$PUBLIC_JELLYFIN_URL"
echo "  Admin: \$SERVICE_USER"
echo
echo "👥 Viewer kullanıcıları:"
printf '  - %s\n' "\${VIEWERS[@]}"
echo
echo "🔐 Viewer şifre kaynakları:"
echo "  ATLON_PASS / ELIFEZEL_PASS / TULUMBA_PASS (Orhan default değil)"
echo
echo "⚠️ Kullanıcılar ilk login sonrası şifre değiştirebilir."
EOF

echo
echo "✅ config/jellyfin/01-jellyfin-libraries-and-users.sh tamamlandı."
echo
echo "📺 Jellyfin URL:"
echo "http://$VM106_IP:8096"
echo
echo "👤 Admin:"
echo "$SERVICE_USER"
echo
echo "🔐 Viewer şifre dosyası:"
echo "/root/homelab-secrets/users.env"
