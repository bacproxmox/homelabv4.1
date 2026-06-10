#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "$0")/../lib/core-bridge.sh"
run_core "tasks/vm/102-docker-arr-vm-install.sh"
run_core "tasks/vm/103-network-vm-install.sh"
run_core "tasks/vm/104-nextcloud-vm-install.sh"
run_core "tasks/vm/105-homeassistant-vm-install.sh"
run_core "tasks/vm/106-media-ai-vm-install.sh"
run_core "tasks/vm/107-chia-farmer-vm-install.sh"
run_core "tasks/vm/110-pbs-backup-vm-install.sh"
