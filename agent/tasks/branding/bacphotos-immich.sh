#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/_vendor-wrapper.sh"
run_vendor "$AGENT/branding/vendor/homelab-bacphotos-immich-title-fix-v6/homelab-bacphotos-immich-title-fix-v6/apply-bacphotos-immich-title-fix-v6.sh" "${1:-status}"
