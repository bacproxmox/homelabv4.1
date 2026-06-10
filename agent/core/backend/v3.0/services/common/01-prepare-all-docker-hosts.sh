#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "prepare-all-docker-hosts"
source "$ROOT_DIR/utils/remote.sh"

for vm in 102 103 104 105 106 107; do
  echo "Preparing Docker host: VM$vm"
  run_remote_script "$vm" "$ROOT_DIR/services/common/00-prepare-docker-host.sh"
done

echo
if [[ "${HOMELAB_RUN_GPU_REPAIR_DURING_PREPARE:-0}" == "1" && -x "$ROOT_DIR/maintenance/repair/repair-gpu-passthrough.sh" ]]; then
  echo "Running VM106/VM107 GPU passthrough + driver validation because HOMELAB_RUN_GPU_REPAIR_DURING_PREPARE=1."
  bash "$ROOT_DIR/maintenance/repair/repair-gpu-passthrough.sh" || echo "GPU repair/validation returned a warning; retry from Repair if needed."
else
  echo "GPU passthrough/driver repair skipped during Docker host preparation."
  echo "Run Repair > GPU passthrough repair separately if VM106 /dev/dri or VM107 GPU needs attention."
fi
