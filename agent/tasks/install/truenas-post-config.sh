#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/core-bridge.sh"

SECRETS="/root/homelab-secrets/truenas-login.env"

if [[ -f "$SECRETS" ]]; then
  # shellcheck disable=SC1090
  source "$SECRETS"
  TRUENAS_PASS_COMPAT="${TRUENAS_SSH_PASS:-${TRUENAS_PASS:-${TRUENAS_ADMIN_PASSWORD:-}}}"
  if [[ -n "$TRUENAS_PASS_COMPAT" && -z "${TRUENAS_SSH_PASS:-}" ]]; then
    printf 'TRUENAS_SSH_PASS=%q\n' "$TRUENAS_PASS_COMPAT" >> "$SECRETS"
    export TRUENAS_SSH_PASS="$TRUENAS_PASS_COMPAT"
  fi
fi

export TRUENAS_SSH_READY_ASSUMED=1
export TRUENAS_SKIP_BOOT_FIX=1

run_core "flows/truenas/postinstall-and-storage.sh"
