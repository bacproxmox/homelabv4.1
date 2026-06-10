#!/usr/bin/env bash
set -Eeuo pipefail

echo
echo "===== SATA/SAS SMART health ====="
export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"
apt-get update -y >/dev/null 2>&1 || true
apt-get install -y smartmontools >/dev/null 2>&1 || true

warn=0
lsblk -dn -o NAME,MODEL,SERIAL,SIZE,TYPE | sed 's/[[:space:]][[:space:]]*/ /g' || true

while read -r dev type; do
  [[ "$type" == "disk" ]] || continue
  [[ "$dev" == sd* || "$dev" == hd* ]] || continue
  path="/dev/$dev"
  echo
  echo "--- $path ---"
  out="$(smartctl -A "$path" 2>/dev/null || true)"
  echo "$out" | egrep -i 'Temperature_Celsius|Airflow_Temperature|Current_Pending_Sector|Offline_Uncorrectable|Reallocated_Sector|UDMA_CRC_Error' || true
  if echo "$out" | awk '/Current_Pending_Sector|Offline_Uncorrectable|Reallocated_Sector_Ct|UDMA_CRC_Error_Count/ && $10 ~ /^[0-9]+$/ && $10 > 0 {bad=1} END{exit bad?0:1}'; then
    echo "Uyari: $path uzerinde sector/kablo/CRC turu SMART uyarisi var."
    warn=1
  fi
done < <(lsblk -dn -o NAME,TYPE)

exit "$warn"
