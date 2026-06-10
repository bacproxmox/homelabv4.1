#!/usr/bin/env bash
set -Eeuo pipefail

echo
echo "===== NVMe health ====="
export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"
apt-get update -y >/dev/null 2>&1 || true
apt-get install -y nvme-cli >/dev/null 2>&1 || true

warn=0
nvme list 2>/dev/null || true

for dev in /dev/nvme[0-9]; do
  [[ -e "$dev" ]] || continue
  echo
  echo "--- $dev ---"
  out="$(nvme smart-log "$dev" 2>/dev/null || true)"
  echo "$out" | egrep -i 'critical_warning|temperature|media_errors|num_err_log_entries|percentage_used|available_spare' || true
  media="$(awk -F: '/media_errors/ {gsub(/[, ]/,"",$2); print $2}' <<<"$out" | head -n1)"
  crit="$(awk -F: '/critical_warning/ {gsub(/[, ]/,"",$2); print $2}' <<<"$out" | head -n1)"
  if [[ "${media:-0}" =~ ^[0-9]+$ && "${media:-0}" -gt 0 ]]; then
    echo "Uyari: $dev media_errors > 0: $media"
    warn=1
  fi
  if [[ -n "${crit:-}" && "$crit" != "0" && "$crit" != "0x0" ]]; then
    echo "Uyari: $dev critical_warning: $crit"
    warn=1
  fi
done

exit "$warn"
