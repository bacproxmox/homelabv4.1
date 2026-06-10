#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while true; do
  clear || true
  cat <<'MENU'
=========================================
 Homelab v2.4.7 - Auth / SSO Experiments
=========================================
1) Jellyfin / Bacsflix Google SSO notes
2) Seerr / Bacneyplus Google SSO notes
3) Cloudflare Access Google login notes
4) Back
MENU
  read -r -p "Seçim: " choice
  case "$choice" in
    1) bash "$SCRIPT_DIR/jellyfin-google-sso-notes.sh" ;;
    2) bash "$SCRIPT_DIR/seerr-google-sso-notes.sh" ;;
    3) bash "$SCRIPT_DIR/cloudflare-access-google-notes.sh" ;;
    4) exit 0 ;;
    *) echo "Geçersiz seçim"; sleep 2 ;;
  esac
  read -r -p "Devam için Enter..." _
done
