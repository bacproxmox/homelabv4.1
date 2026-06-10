#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMELAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$HOMELAB_ROOT/lib/core/runner.sh"

homelab_run "tasks/truenas/postinstall/10-fix-boot.sh"
homelab_run "tasks/truenas/postinstall/20-discover-ip.sh"
homelab_run "tasks/truenas/postinstall/30-refresh-known-host.sh"
export TRUENAS_SKIP_BOOT_FIX=1
homelab_run "tasks/truenas/postinstall/40-import-pools-create-api-key-and-network.sh"
