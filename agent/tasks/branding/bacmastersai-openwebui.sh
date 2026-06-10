#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/_vendor-wrapper.sh"
run_vendor "$AGENT/branding/vendor/bacmastersai-openwebui/apply-bacmasters-ai-openwebui-theme-v4-polish.sh" "${1:-status}"
