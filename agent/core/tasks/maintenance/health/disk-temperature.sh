#!/usr/bin/env bash
set -Eeuo pipefail

echo
echo "===== Disk temperature ====="
export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"
apt-get update -y >/dev/null 2>&1 || true
apt-get install -y smartmontools nvme-cli jq >/dev/null 2>&1 || true

warn=0

nvme_temp_c() {
  local dev="$1" json temp
  json="$(nvme smart-log -o json "$dev" 2>/dev/null || true)"
  if [[ -n "$json" ]] && command -v jq >/dev/null 2>&1; then
    temp="$(jq -r '(.temperature // empty)' <<<"$json" 2>/dev/null || true)"
    if [[ "$temp" =~ ^[0-9]+$ ]]; then
      # nvme-cli JSON normally reports Kelvin. Some older builds may already
      # report Celsius; treat values above 200 as Kelvin and convert safely.
      if [[ "$temp" -gt 200 ]]; then
        echo $((temp - 273))
      else
        echo "$temp"
      fi
      return 0
    fi
  fi

  # Fallback: parse the first Celsius value from human output, e.g.
  # "temperature : 37 C (310 Kelvin)". Avoid concatenating Fahrenheit/Kelvin.
  nvme smart-log "$dev" 2>/dev/null \
    | awk '/^temperature[[:space:]]*:/ { for (i=1; i<=NF; i++) if ($i ~ /^[0-9]+$/ && $(i+1) ~ /^C/) { print $i; exit } }'
}

for dev in /dev/nvme[0-9]; do
  [[ -e "$dev" ]] || continue
  temp="$(nvme_temp_c "$dev" || true)"
  [[ -n "${temp:-}" ]] || continue
  echo "$dev temperature=${temp}C"
  if [[ "$temp" =~ ^[0-9]+$ && "$temp" -ge 70 ]]; then
    echo "Uyari: NVMe sicakligi yuksek: $dev ${temp}C"
    warn=1
  fi
done

while read -r dev type; do
  [[ "$type" == "disk" ]] || continue
  [[ "$dev" == sd* || "$dev" == hd* ]] || continue
  path="/dev/$dev"
  out="$(smartctl -A "$path" 2>/dev/null || true)"
  temp="$(echo "$out" | awk '/Temperature_Celsius|Airflow_Temperature/ {print $10; exit}')"
  [[ -n "${temp:-}" ]] || continue
  echo "$path temperature=${temp}C"
  if [[ "$temp" =~ ^[0-9]+$ && "$temp" -ge 60 ]]; then
    echo "Uyari: disk sicakligi yuksek: $path ${temp}C"
    warn=1
  fi
done < <(lsblk -dn -o NAME,TYPE)

exit "$warn"
