#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/../lib/core-bridge.sh"
run_core "flows/truenas/create-vm-and-checkpoint.sh"
