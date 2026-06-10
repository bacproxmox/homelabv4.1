#!/usr/bin/env bash
set -Eeuo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

failed=()

run_pack() {
  local label="$1"
  shift
  echo
  echo "=== Branding pack: $label ==="
  if "$@"; then
    echo "BRANDING_PACK_OK: $label"
  else
    local code=$?
    echo "BRANDING_PACK_FAILED: $label (exit $code)"
    failed+=("$label")
  fi
}

run_pack "BacsCloud Nextcloud" bash "$DIR/bacscloud-nextcloud-apply.sh"
run_pack "Bacsflix Jellyfin" bash "$DIR/bacsflix-jellyfin-apply.sh"
run_pack "BacStatus Uptime Kuma" bash "$DIR/bacstatus-uptime-kuma.sh" apply
run_pack "BacHome Home Assistant" bash "$DIR/bachome-homeassistant.sh" apply
run_pack "BacPhotos Immich" bash "$DIR/bacphotos-immich.sh" apply
run_pack "BacmastersAI OpenWebUI" bash "$DIR/bacmastersai-openwebui.sh" apply

echo
if [[ "${#failed[@]}" -gt 0 ]]; then
  echo "BRANDING_NEEDS_ATTENTION: ${#failed[@]} pack(s) failed."
  printf ' - %s\n' "${failed[@]}"
  echo "Full install will continue. Re-run failed packs from the Branding tab after reviewing this log."
else
  echo "Safe branding wave completed without failed packs."
fi

exit 0
