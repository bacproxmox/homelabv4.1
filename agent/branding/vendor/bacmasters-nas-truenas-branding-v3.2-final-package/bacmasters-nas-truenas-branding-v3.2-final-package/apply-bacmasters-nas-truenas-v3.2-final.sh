#!/usr/bin/env bash
set -Eeuo pipefail

# Bacmaster's NAS final branding bundle for TrueNAS SCALE, prepared for Homelab v3.2.
# Run this on the Proxmox host as root.
#
# What it does:
#   1) Applies Bacmaster's NAS login banner + visible text + login wallpaper base (v7)
#   2) Cleans the leftover original TrueNAS topbar wordmark/S artifact (v8)
#   3) Forces the login wallpaper to stay visible after route/cache changes (v9)
#
# It does not touch pools, datasets, shares, middleware settings, users, or services.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"

V7="$SCRIPTS_DIR/apply-truenas-bacmasters-ui-branding-v7.sh"
V8="$SCRIPTS_DIR/fix-truenas-bacmasters-topbar-s-v8.sh"
V9="$SCRIPTS_DIR/fix-truenas-bacmasters-login-wallpaper-v9.sh"

for f in "$V7" "$V8" "$V9"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: Missing bundled script: $f"
    exit 10
  fi
  chmod +x "$f"
done

echo
printf '%s\n' "============================================================"
printf '%s\n' " Bacmaster's NAS branding for TrueNAS SCALE - Homelab v3.2"
printf '%s\n' "============================================================"
echo

echo "==> Step 1/3: Apply base UI/login branding v7"
bash "$V7" apply

echo
echo "==> Step 2/3: Apply topbar S cleanup v8"
bash "$V8"

echo
echo "==> Step 3/3: Apply login wallpaper force-fix v9"
bash "$V9"

echo
echo "✅ Bacmaster's NAS final branding applied."
echo
echo "Open a NEW private/incognito window or press Ctrl+F5 twice:"
echo "  http://${TRUENAS_IP:-192.168.50.101}/ui/signin?bacmasters_final=1"
echo "  http://${TRUENAS_IP:-192.168.50.101}/ui/dashboard?bacmasters_final=1"
echo
