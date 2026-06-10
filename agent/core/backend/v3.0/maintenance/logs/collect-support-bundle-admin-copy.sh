#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

PROXMOX_HOST="${PROXMOX_HOST:-192.168.50.100}"
PROXMOX_USER="${PROXMOX_USER:-root}"
DEFAULT_WIN_PATH='C:\Users\Burhan\Desktop\Homelab Project\Logs'

strip_outer_quotes() {
  local s="$1"
  s="${s%$'\r'}"
  if [[ "$s" == \"*\" && "$s" == *\" ]]; then
    s="${s:1:${#s}-2}"
  elif [[ "$s" == \'*\' && "$s" == *\' ]]; then
    s="${s:1:${#s}-2}"
  fi
  printf '%s' "$s"
}

ps_quote() {
  # PowerShell double-quoted string escaping: backtick and double quote.
  local s="$1"
  s="${s//\`/\`\`}"
  s="${s//\"/\`\"}"
  printf '"%s"' "$s"
}

latest_bundle() {
  ls -1t /root/homelab-support*.tar.gz 2>/dev/null | head -n1 || true
}

cat <<'BANNER'
============================================================
 Homelab v2.4.7 - Collect support bundle & prepare admin copy
============================================================
BANNER

echo
before_bundle="$(latest_bundle)"

echo "[1/3] Redacted support bundle oluşturuluyor..."
bash "$ROOT_DIR/maintenance/logs/collect-support-bundle.sh"

after_bundle="$(latest_bundle)"
if [[ -z "$after_bundle" ]]; then
  echo "❌ Support bundle tar.gz bulunamadı."
  exit 1
fi

if [[ -n "$before_bundle" && "$after_bundle" == "$before_bundle" ]]; then
  echo "⚠️ Yeni bundle tespit edilemedi; en güncel mevcut bundle kullanılacak: $after_bundle"
fi

echo
echo "[2/3] Windows hedef klasörü alınacak."
echo "Örnek: $DEFAULT_WIN_PATH"
read -r -p "Windows hedef klasörü [varsayılan: $DEFAULT_WIN_PATH]: " WIN_PATH_RAW
WIN_PATH_RAW="${WIN_PATH_RAW:-$DEFAULT_WIN_PATH}"
WIN_PATH="$(strip_outer_quotes "$WIN_PATH_RAW")"

if [[ -z "$WIN_PATH" ]]; then
  echo "❌ Windows path boş olamaz."
  exit 1
fi

PS_PATH="$(ps_quote "$WIN_PATH")"
REMOTE_LOGS="${PROXMOX_USER}@${PROXMOX_HOST}:/root/homelab-logs"
REMOTE_SUPPORT_ALL="${PROXMOX_USER}@${PROXMOX_HOST}:/root/homelab-support*"
REMOTE_BUNDLE="${PROXMOX_USER}@${PROXMOX_HOST}:${after_bundle}"

COMMAND_FILE="/root/homelab-logs/last-support-bundle-windows-copy.ps1"
mkdir -p /root/homelab-logs
cat > "$COMMAND_FILE" <<EOF2
# Homelab support bundle copy command
# Generated on: $(date -Is)
# Run this in Windows PowerShell on your admin PC.

\$Dest = $PS_PATH
New-Item -ItemType Directory -Force -Path \$Dest | Out-Null
scp -r "$REMOTE_LOGS" "$REMOTE_SUPPORT_ALL" \$Dest
EOF2
chmod 600 "$COMMAND_FILE"

echo
echo "[3/3] Windows PowerShell komutu hazır."
echo
echo "⚠️ Bu menü Proxmox içinde çalıştığı için Windows path'e doğrudan dosya yazamaz."
echo "Aşağıdaki komutu Windows PowerShell tarafında çalıştırmalısın:"
echo
cat "$COMMAND_FILE"
echo
echo "Oluşturulan bundle: $after_bundle"
echo "PowerShell komut dosyası Proxmox'ta da kaydedildi: $COMMAND_FILE"
echo
echo "Tek satır istersen:"
echo "New-Item -ItemType Directory -Force -Path $PS_PATH | Out-Null; scp -r \"$REMOTE_LOGS\" \"$REMOTE_SUPPORT_ALL\" $PS_PATH"
