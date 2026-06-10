#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMELAB_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$HOMELAB_ROOT/lib/core/runner.sh"

warn=0
homelab_run "tasks/maintenance/health/nvme-health.sh" || warn=1
homelab_run "tasks/maintenance/health/disk-smart-health.sh" || warn=1
homelab_run "tasks/maintenance/health/disk-temperature.sh" || warn=1
homelab_run "tasks/maintenance/health/kernel-disk-errors.sh" || warn=1

legacy="$HOMELAB_ROOT/backend/v3.0/maintenance/health/full-health-check.sh"
if [[ -f "$legacy" ]]; then
  bash "$legacy" || warn=1
else
  echo "Uyari: legacy full-health-check bulunamadi: $legacy"
  warn=1
fi

exit "$warn"
