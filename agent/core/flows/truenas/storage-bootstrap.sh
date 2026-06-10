#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMELAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$HOMELAB_ROOT/lib/core/runner.sh"

homelab_run "tasks/truenas/storage/10-api-readiness.sh"
homelab_run "tasks/truenas/storage/20-bootstrap-users-datasets-shares.sh"
homelab_run "tasks/truenas/storage/90-final-verify.sh"
