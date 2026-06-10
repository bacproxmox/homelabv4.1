#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOMELAB_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$HOMELAB_ROOT/lib/core/runner.sh"

echo "TrueNAS VM101 modular create flow basliyor..."
homelab_run "tasks/iso/truenas/discover-stable-version.sh"
homelab_run "tasks/iso/truenas/download-iso.sh"
homelab_run "tasks/iso/truenas/verify-iso.sh"
export HOMELAB_ALLOW_STORAGE_CREATE="${HOMELAB_ALLOW_STORAGE_CREATE:-1}"
homelab_run "tasks/proxmox/storage/ensure-vm-storage.sh"
homelab_run "tasks/vm/truenas/10-create-vm-shell.sh"
homelab_run "tasks/vm/truenas/20-attach-install-iso.sh"
homelab_run "tasks/vm/truenas/30-attach-passthrough-disks.sh"
homelab_run "tasks/vm/truenas/40-verify-config.sh"
echo "TrueNAS VM101 create flow tamam."
