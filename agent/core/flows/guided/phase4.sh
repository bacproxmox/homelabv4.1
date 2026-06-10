#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMELAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$HOMELAB_ROOT/lib/core/runner.sh"

homelab_run "tasks/config/smtp/write-service-smtp-reference.sh" || true
homelab_run "tasks/config/uptime-kuma/auto-config.sh" || true
homelab_run "tasks/config/pbs/backup-automation.sh" || true
homelab_run "tasks/services/chia/install.sh"
