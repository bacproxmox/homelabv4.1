#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# Compatibility shim: v3.1 logging lives in lib/core.
source "$ROOT_DIR/lib/core/logging.sh"
