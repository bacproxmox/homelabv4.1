#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMELAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$HOMELAB_ROOT/lib/core/runner.sh"
source "$HOMELAB_ROOT/lib/truenas/checkpoint.sh"

# v3.1.1 stabilization:
# If the user already completed TrueNAS manual install + WebUI/SSH checkpoint,
# never rerun VM creation/disk validation on resume. This avoids failing a
# rerun because a passthrough disk temporarily disappeared after checkpoint.
if truenas_checkpoint_already_done "$TRUENAS_FINAL_IP"; then
  echo "TrueNAS checkpoint zaten tamam; VM create/ISO/passthrough dogrulama adimi atlandi."
  mark_fresh_truenas_api_required
  exit 0
fi

homelab_run "flows/truenas/create-vm.sh"
homelab_run "flows/truenas/manual-install-checkpoint.sh"
