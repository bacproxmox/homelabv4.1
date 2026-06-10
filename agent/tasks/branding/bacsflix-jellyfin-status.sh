#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/_vendor-wrapper.sh"
run_vendor "$AGENT/branding/vendor/homelabv32-bacsflix-jellyfin-branding/homelabv32-bacsflix-jellyfin-branding/backend/v3.0/additionals/branding/bacsflix-jellyfin/20-apply-bacsflix-jellyfin-branding.sh" status
