#!/usr/bin/env bash
set -Eeuo pipefail

source "$(dirname "$0")/../lib/core-bridge.sh"

if [[ ! -f /root/homelab-secrets/chia-bootstrap.env ]]; then
  echo "SECRETS_MISSING: Chia bootstrap config is missing at /root/homelab-secrets/chia-bootstrap.env"
  echo "Open the Homelabv4 Secrets page, fill the Chia fields, upload secrets, then rerun this step."
  exit 12
fi

export HOMELAB_CHIA_DB_BOOTSTRAP_START_ONLY=1
export HOMELAB_CHIA_DEFER_DB_START=0
run_core "tasks/services/chia/db-bootstrap-start.sh"
