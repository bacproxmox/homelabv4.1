#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/_vendor-wrapper.sh"
run_vendor "$AGENT/branding/vendor/bacscloud-nextcloud-branding-v32-package/additionals/branding/30-apply-bacscloud-nextcloud-branding.sh" apply
