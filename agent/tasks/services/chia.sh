#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "$0")/../lib/core-bridge.sh"

require_secret_file() {
  local path="$1" label="$2"
  if [[ -f "$path" ]]; then
    return 0
  fi
  echo "SECRETS_MISSING: $label is missing at $path"
  echo "Open the Homelabv4 Secrets page, fill the Chia fields, upload secrets, then rerun this step."
  exit 12
}

require_secret_file "/root/homelab-secrets/chia-mnemonic.env" "Chia mnemonic"
require_secret_file "/root/homelab-secrets/chia-bootstrap.env" "Chia bootstrap config"
export HOMELAB_CHIA_DEFER_DB_START=1
run_core "tasks/services/chia/install.sh"
