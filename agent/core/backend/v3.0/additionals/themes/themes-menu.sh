#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while true; do
  clear || true
  cat <<'MENU'
=========================================
 Homelab v2.4.7 - Themes / Branding
=========================================
1) Apply BacsCloud theme to Nextcloud
2) Apply Bacsflix theme to Jellyfin
3) Apply Avengers theme to Seerr
4) Back
MENU
  read -r -p "Seçim: " choice
  case "$choice" in
    1) bash "$SCRIPT_DIR/nextcloud-to-bacscloud-theme.sh" ;;
    2) bash "$SCRIPT_DIR/jellyfin-bacsflix-theme.sh" ;;
    3) bash "$SCRIPT_DIR/seerr-to-avengers-theme.sh" ;;
    4) exit 0 ;;
    *) echo "Geçersiz seçim"; sleep 2 ;;
  esac
  read -r -p "Devam için Enter..." _
done
