#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/../lib/core-bridge.sh"
planned_branding_task "${1:-status}" "Homelabv4 Windows Electron app" "Bacmaster"
