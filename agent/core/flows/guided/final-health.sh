#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMELAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$HOMELAB_ROOT/lib/core/runner.sh"

warn=0
homelab_run "tasks/maintenance/health/vm-resource-audit.sh" || warn=1
homelab_run "tasks/maintenance/health/full-health-check.sh" || warn=1
homelab_run "tasks/maintenance/health/full-service-audit.sh" || warn=1
exit "$warn"
