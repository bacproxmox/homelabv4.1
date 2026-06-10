#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while true; do
  clear || true
  cat <<'MENU'
=========================================
 Homelab v2.4.7 - Profile Pictures
=========================================
1) Configure Jellyfin avatars
2) Configure Nextcloud avatars
3) Configure Immich avatars
4) Configure Open WebUI avatars
5) Back
MENU
  read -r -p "Seçim: " choice
  case "$choice" in
    1) bash "$SCRIPT_DIR/configure-jellyfin-avatars.sh" ;;
    2) bash "$SCRIPT_DIR/configure-nextcloud-avatars.sh" ;;
    3) bash "$SCRIPT_DIR/configure-immich-avatars.sh" ;;
    4) bash "$SCRIPT_DIR/configure-openwebui-avatars.sh" ;;
    5) exit 0 ;;
    *) echo "Geçersiz seçim"; sleep 2 ;;
  esac
  read -r -p "Devam için Enter..." _
done
