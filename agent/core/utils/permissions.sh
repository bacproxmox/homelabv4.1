#!/usr/bin/env bash
set -Eeuo pipefail
normalize_stack_permissions(){ local p="$1"; mkdir -p "$p"; chown -R 1000:1000 "$p" 2>/dev/null || true; chmod -R ug+rwX,o-rwx "$p" 2>/dev/null || true; }
ensure_dir_775(){ local p="$1"; mkdir -p "$p"; chown -R 1000:1000 "$p" 2>/dev/null || true; chmod -R 775 "$p" 2>/dev/null || true; }
