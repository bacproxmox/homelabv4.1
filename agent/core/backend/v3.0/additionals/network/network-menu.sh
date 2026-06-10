#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
while true; do
  clear || true
  cat <<'MENU'
=========================================
 Homelab v2.4.7 - Network Additionals
=========================================
1) Install optional AdGuard Home on VM103
2) Back
MENU
  read -r -p "Seçim: " choice
  case "$choice" in
    1) bash "$ROOT_DIR/additionals/network/adguard-home-install.sh" ;;
    2) exit 0 ;;
    *) echo "Geçersiz seçim"; sleep 2 ;;
  esac
  read -r -p "Devam için Enter..." _
done
