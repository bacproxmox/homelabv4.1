#!/usr/bin/env bash
set -Eeuo pipefail

echo
echo "🧪 Homelab v2.4.7 - Hardware preflight"
echo "Bu kontrol kurulumdan önce SMART/NVMe/ısı/kablo sinyallerini özetler."
echo "Uyarı varsa kurulum otomatik durmaz; ama kırmızı disk uyarıları ciddiye alınmalı."

export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null 2>&1 || true
apt-get install -y smartmontools nvme-cli >/dev/null 2>&1 || true

warn=0

echo
echo "===== NVMe list ====="
nvme list 2>/dev/null || true

echo
echo "===== lsblk disk özeti ====="
lsblk -dn -o NAME,MODEL,SERIAL,SIZE,TYPE | sed 's/[[:space:]][[:space:]]*/ /g' || true

echo
echo "===== NVMe SMART hızlı kontrol ====="
for n in /dev/nvme[0-9]; do
  [[ -e "$n" ]] || continue
  echo "--- $n ---"
  out="$(nvme smart-log "$n" 2>/dev/null || true)"
  echo "$out" | egrep -i 'critical_warning|temperature|media_errors|num_err_log_entries|percentage_used|available_spare' || true
  media="$(awk -F: '/media_errors/ {gsub(/[, ]/,"",$2); print $2}' <<<"$out" | head -n1)"
  crit="$(awk -F: '/critical_warning/ {gsub(/[, ]/,"",$2); print $2}' <<<"$out" | head -n1)"
  if [[ "${media:-0}" =~ ^[0-9]+$ && "${media:-0}" -gt 0 ]]; then
    echo "⚠️ $n media_errors > 0: $media"
    warn=1
  fi
  if [[ -n "${crit:-}" && "$crit" != "0" && "$crit" != "0x0" ]]; then
    echo "⚠️ $n critical_warning: $crit"
    warn=1
  fi
done

echo
echo "===== SATA/SAS SMART hızlı kontrol ====="
while read -r dev type; do
  [[ "$type" == "disk" ]] || continue
  [[ "$dev" == sd* || "$dev" == hd* ]] || continue
  path="/dev/$dev"
  echo "--- $path ---"
  out="$(smartctl -A "$path" 2>/dev/null || true)"
  echo "$out" | egrep -i 'Temperature_Celsius|Airflow_Temperature|Current_Pending_Sector|Offline_Uncorrectable|Reallocated_Sector|UDMA_CRC_Error' || true
  if echo "$out" | awk '/Current_Pending_Sector|Offline_Uncorrectable|Reallocated_Sector_Ct|UDMA_CRC_Error_Count/ && $10 ~ /^[0-9]+$/ && $10 > 0 {bad=1} END{exit bad?0:1}'; then
    echo "⚠️ $path üzerinde sector/kablo/CRC türü SMART uyarısı var."
    warn=1
  fi
  temp="$(echo "$out" | awk '/Temperature_Celsius|Airflow_Temperature/ {print $10; exit}')"
  if [[ "${temp:-0}" =~ ^[0-9]+$ && "${temp:-0}" -ge 60 ]]; then
    echo "⚠️ $path sıcaklık yüksek görünüyor: ${temp}°C"
    warn=1
  fi
done < <(lsblk -dn -o NAME,TYPE)

echo
echo "===== Kernel disk hata özeti ====="
dmesg -T 2>/dev/null | egrep -i 'ata[0-9].*(error|failed|reset)|I/O error|uncorrect|media and data integrity|nvme.*error|CRC' | tail -n 80 || true

echo
if [[ "$warn" -eq 1 ]]; then
  echo "⚠️ Hardware preflight uyarı verdi. Özellikle NVMe media_errors, pending/uncorrectable sector ve 60°C+ disk sıcaklıklarını çözmeden uzun kurulum/test yapmak riskli."
else
  echo "✅ Hardware preflight kritik SMART uyarısı yakalamadı."
fi
