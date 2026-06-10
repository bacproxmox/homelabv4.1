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

JELLYFIN_THEME="${JELLYFIN_THEME:-bacsflix}"
JELLYFIN_BRAND="${JELLYFIN_BRAND:-Bacsflix}"

{
  write_env_header
  write_env_line JELLYFIN_THEME "$JELLYFIN_THEME"
  write_env_line JELLYFIN_BRAND "$JELLYFIN_BRAND"
} > "$TMP/jellyfin-theme.env"

cat > "$TMP/apply-jellyfin-theme.remote.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail

BRANDING_DIR="/opt/homelab/jellyfin/config/jellyfin/config"
BRANDING_XML="$BRANDING_DIR/branding.xml"
THEME="${JELLYFIN_THEME:-bacsflix}"
BRAND="${JELLYFIN_BRAND:-Bacsflix}"

mkdir -p "$BRANDING_DIR"

if [[ -f "$BRANDING_XML" ]]; then
  cp "$BRANDING_XML" "$BRANDING_XML.backup.$(date +%Y%m%d-%H%M%S)"
fi

python3 - "$BRANDING_XML" "$THEME" "$BRAND" <<'PY'
import sys
import xml.etree.ElementTree as ET

path, theme, brand = sys.argv[1:4]
brand = brand.replace('"', '').replace("\\", "")

imports = {
    "finimalism": '@import url("https://cdn.jsdelivr.net/gh/tedhinklater/finimalism@main/Finimalism11.css");',
    "elegantfin": '@import url("https://cdn.jsdelivr.net/gh/lscambo13/ElegantFin@main/Theme/ElegantFin-jellyfin-theme-build-latest-minified.css");',
    "better-jellyfin-ui": '@import url("https://cdn.jsdelivr.net/gh/tromoSM/better-jellyfin-ui@main/theme.css");',
    "abyss": "@import url('https://cdn.jsdelivr.net/gh/AumGupta/abyss-jellyfin@main/abyss.css');",
}

bacsflix_css = f"""
/* Homelab v3.1 Bacsflix branding */
:root {{
  --bacs-red: #e50914;
  --bacs-red-dark: #8f0007;
  --bacs-bg: #030303;
  --bacs-card: #141414;
}}

html, body, .backgroundContainer {{
  background: radial-gradient(circle at top left, #210005 0%, #070707 38%, #000 100%) !important;
}}

.skinHeader,
.skinHeader-withBackground,
.skinHeader.semiTransparent {{
  background: rgba(0,0,0,.92) !important;
  backdrop-filter: blur(10px) !important;
}}

.headerLogo,
.pageTitleWithDefaultLogo {{
  background-image: none !important;
  min-width: 150px !important;
  height: 40px !important;
  display: flex !important;
  align-items: center !important;
  font-size: 0 !important;
}}

.headerLogo img,
.pageTitleWithDefaultLogo img {{
  display: none !important;
}}

.headerLogo::after,
.pageTitleWithDefaultLogo::after,
.adminDrawerLogo::after,
.adminDrawerHeader::after {{
  content: "{brand}";
  color: var(--bacs-red) !important;
  font-family: Impact, Arial Black, system-ui, sans-serif !important;
  font-size: 1.75rem !important;
  font-weight: 900 !important;
  text-shadow: 0 0 12px rgba(229,9,20,.45) !important;
}}

.cardBox,
.visualCardBox,
.cardScalable {{
  background: var(--bacs-card) !important;
  border-radius: 10px !important;
  transition: transform .18s ease, box-shadow .18s ease !important;
}}

.cardBox:hover,
.cardScalable:hover {{
  transform: scale(1.045) !important;
  box-shadow: 0 14px 38px rgba(0,0,0,.8) !important;
  z-index: 10 !important;
}}

.button-submit,
.raised.button-submit,
.emby-button.raised,
.itemProgressBarForeground,
.mdl-slider-background-lower {{
  background: var(--bacs-red) !important;
  color: #fff !important;
}}

.navMenuOption-selected,
.sidebarLink.selected,
.emby-tab-button-active {{
  background: linear-gradient(90deg, rgba(229,9,20,.95), rgba(100,0,5,.45)) !important;
  color: #fff !important;
}}
"""

brand_css = f"""

/* Homelab v3.1 brand label */
.headerLogo img,
.pageTitleWithDefaultLogo img {{
  display: none !important;
}}
.headerLogo::after,
.pageTitleWithDefaultLogo::after {{
  content: "{brand}";
  font-weight: 800 !important;
}}
"""

if theme == "none":
    css = ""
elif theme == "bacsflix":
    css = bacsflix_css
elif theme in imports:
    css = imports[theme] + brand_css
else:
    css = bacsflix_css

root = ET.Element("BrandingOptions")
login = ET.SubElement(root, "LoginDisclaimer")
login.text = ""
custom_css = ET.SubElement(root, "CustomCss")
custom_css.text = css

tree = ET.ElementTree(root)
ET.indent(tree, space="  ", level=0)
tree.write(path, encoding="utf-8", xml_declaration=True)
print(f"Updated {path} with theme={theme}")
PY

chown -R 1000:1000 /opt/homelab/jellyfin/config/jellyfin 2>/dev/null || true

if [[ -d /opt/homelab/jellyfin ]]; then
  cd /opt/homelab/jellyfin
  docker compose restart jellyfin >/dev/null || true
fi

echo "Jellyfin tema uygulandi: $THEME ($BRAND)"
REMOTE

password_rscp "$TMP/jellyfin-theme.env" 106 /tmp/homelab-jellyfin-theme.env
password_rscp "$TMP/apply-jellyfin-theme.remote.sh" 106 /tmp/apply-jellyfin-theme.remote.sh
password_sudo_bash 106 "set -a; source /tmp/homelab-jellyfin-theme.env; set +a; bash /tmp/apply-jellyfin-theme.remote.sh"
