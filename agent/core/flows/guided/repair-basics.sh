#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMELAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$HOMELAB_ROOT/lib/core/runner.sh"

homelab_run "tasks/maintenance/repair/repair-gpu-passthrough.sh" || true
homelab_run "tasks/maintenance/repair/repair-chia-plot-disks.sh" || true
homelab_run "tasks/maintenance/repair/repair-nfs-mounts.sh" || true
homelab_run "tasks/config/nextcloud/local-and-cloudflare-fix.sh" || true
