#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/../lib/core-bridge.sh"

require_secret_file() {
  local path="$1" label="$2"
  if [[ -f "$path" ]]; then
    return 0
  fi
  echo "SECRETS_MISSING: $label is missing at $path"
  echo "Open the Homelabv4 Secrets page, fill the Chia fields, upload secrets, then rerun Full Install."
  exit 12
}

run_core "tasks/services/common/prepare-all-docker-hosts.sh"
run_core "tasks/services/arr/install.sh"
run_core "tasks/services/seerr/install.sh"
run_core "tasks/services/uptime-kuma/install.sh"
run_core "tasks/services/nextcloud/install.sh"
run_core "tasks/services/jellyfin/install.sh"
run_core "tasks/services/immich/install.sh"
run_core "tasks/services/ollama/install.sh"
run_core "tasks/services/lidarr/install.sh"
run_core "tasks/services/homeassistant/install.sh"
run_core "tasks/services/pbs/install.sh"
require_secret_file "/root/homelab-secrets/chia-mnemonic.env" "Chia mnemonic"
require_secret_file "/root/homelab-secrets/chia-bootstrap.env" "Chia bootstrap config"
run_core "tasks/services/chia/install.sh"
