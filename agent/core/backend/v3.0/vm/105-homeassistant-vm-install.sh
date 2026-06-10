#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/logging.sh"
start_log "vm-105-homeassistant"
source "$SCRIPT_DIR/../lib/vm-cloudinit-common.sh"
VM105_RAM_MB="${VM105_RAM_MB:-2048}"
VM105_BALLOON_MB="${VM105_BALLOON_MB:-1024}"
VM105_ZRAM_MB="${VM105_ZRAM_MB:-1024}"
VM105_CORES="${VM105_CORES:-2}"
export VM105_BALLOON_MB VM105_ZRAM_MB
create_ubuntu_vm 105 "homeassistant" "192.168.50.105/24" "$VM105_RAM_MB" "$VM105_CORES" 64G "yes" "none"
