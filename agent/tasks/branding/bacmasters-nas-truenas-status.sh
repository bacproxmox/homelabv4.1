#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/_vendor-wrapper.sh"
run_vendor "$AGENT/branding/vendor/bacmasters-nas-truenas-branding-v3.2-final-package/bacmasters-nas-truenas-branding-v3.2-final-package/status-bacmasters-nas-truenas-v3.2.sh" status
