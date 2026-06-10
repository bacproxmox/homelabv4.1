#!/usr/bin/env bash
set -Eeuo pipefail
set +H

export TERM=xterm

echo
echo "🎨 Homelab v2.4.7 - Jellyfin Bacsflix Theme Configurator"
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

apt update
apt install -y sshpass

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
    "$tmp_local" "$SSH_USER@$ip:/tmp/homelab-jellyfin-theme.sh" >/dev/null

  sshpass -p "$SSH_PASS" ssh "${SSH_OPTS[@]}" \
    "$SSH_USER@$ip" \
    "echo '$SSH_PASS' | sudo -S -p '' bash /tmp/homelab-jellyfin-theme.sh"

  rm -f "$tmp_local"
}

run_ssh "$VM106_IP" <<'EOF'
set -Eeuo pipefail
set +H

cd /opt/homelab/jellyfin

echo "🎨 Bacsflix CSS branding.xml içine yazılıyor..."

BRANDING_DIR="/opt/homelab/jellyfin/config/jellyfin/config"
BRANDING_XML="$BRANDING_DIR/branding.xml"

mkdir -p "$BRANDING_DIR"

if [[ -f "$BRANDING_XML" ]]; then
  cp "$BRANDING_XML" "$BRANDING_XML.backup.$(date +%Y%m%d-%H%M%S)"
fi

python3 - "$BRANDING_XML" <<'PY'
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]

css = r'''
/* Bacsflix Theme - Homelab v2.4.6 */

:root {
  --bacs-red: #e50914;
  --bacs-red-dark: #8f0007;
  --bacs-bg: #030303;
  --bacs-card: #141414;
}

/* Background */
html, body, .backgroundContainer {
  background: radial-gradient(circle at top left, #210005 0%, #070707 38%, #000 100%) !important;
}

/* Top header */
.skinHeader,
.skinHeader-withBackground,
.skinHeader.semiTransparent {
  background: rgba(0,0,0,.92) !important;
  backdrop-filter: blur(10px) !important;
}

/* Replace main Jellyfin logo/title with Bacsflix */
.headerLogo,
.pageTitleWithDefaultLogo {
  background-image: none !important;
  width: auto !important;
  min-width: 140px !important;
  height: 40px !important;
  display: flex !important;
  align-items: center !important;
  font-size: 0 !important;
}

.headerLogo img,
.pageTitleWithDefaultLogo img {
  display: none !important;
}

.headerLogo::after,
.pageTitleWithDefaultLogo::after {
  content: "Bacsflix";
  color: var(--bacs-red) !important;
  font-family: Impact, Arial Black, system-ui, sans-serif !important;
  font-size: 1.75rem !important;
  font-weight: 900 !important;
  letter-spacing: -0.04em !important;
  text-shadow: 0 0 12px rgba(229,9,20,.45) !important;
}

/* Drawer/admin logo */
.adminDrawerLogo img {
  display: none !important;
}

.adminDrawerLogo::after,
.adminDrawerHeader::after {
  content: "Bacsflix";
  color: var(--bacs-red) !important;
  font-size: 1.5rem !important;
  font-weight: 900 !important;
  padding-left: .75rem !important;
}

/* Cards */
.cardBox,
.visualCardBox,
.cardScalable {
  background: var(--bacs-card) !important;
  border-radius: 10px !important;
  transition: transform .18s ease, box-shadow .18s ease !important;
}

.cardBox:hover,
.cardScalable:hover {
  transform: scale(1.045) !important;
  box-shadow: 0 14px 38px rgba(0,0,0,.8) !important;
  z-index: 10 !important;
}

/* Buttons/accent */
.button-submit,
.raised.button-submit,
.emby-button.raised {
  background: linear-gradient(135deg, var(--bacs-red), var(--bacs-red-dark)) !important;
  color: #fff !important;
  border-radius: 6px !important;
  font-weight: 700 !important;
}

/* Selected nav */
.navMenuOption-selected,
.sidebarLink.selected,
.emby-tab-button-active {
  background: linear-gradient(90deg, rgba(229,9,20,.95), rgba(100,0,5,.45)) !important;
  color: #fff !important;
}

/* Login page */
#loginPage {
  background: radial-gradient(circle at top, #260005 0%, #070707 45%, #000 100%) !important;
}

.manualLoginForm::before {
  content: "Bacsflix";
  display: block;
  color: var(--bacs-red);
  font-family: Impact, Arial Black, system-ui, sans-serif;
  font-size: 2.8rem;
  font-weight: 900;
  letter-spacing: -0.05em;
  margin-bottom: 1rem;
  text-align: center;
  text-shadow: 0 0 18px rgba(229,9,20,.5);
}

/* Inputs */
.emby-input,
.emby-select,
.emby-textarea {
  background-color: rgba(20,20,20,.95) !important;
  border-color: rgba(255,255,255,.14) !important;
  color: #fff !important;
}

/* Progress/accent */
.itemProgressBarForeground,
.mdl-slider-background-lower {
  background-color: var(--bacs-red) !important;
}
'''

root = ET.Element("BrandingOptions")

login = ET.SubElement(root, "LoginDisclaimer")
login.text = ""

custom_css = ET.SubElement(root, "CustomCss")
custom_css.text = css

tree = ET.ElementTree(root)
ET.indent(tree, space="  ", level=0)
tree.write(path, encoding="utf-8", xml_declaration=True)

print(f"Updated {path}")
PY

chown -R 1000:1000 /opt/homelab/jellyfin/config/jellyfin

echo "🔄 Jellyfin restart ediliyor..."
docker compose restart jellyfin >/dev/null

echo "✅ Bacsflix teması dosyadan uygulandı."
EOF

echo
echo "✅ 09-configure-jellyfin-theme.sh tamamlandı."
echo "Kontrol: http://$VM106_IP:8096"
echo
echo "Tarayıcıda Ctrl + F5 yap."