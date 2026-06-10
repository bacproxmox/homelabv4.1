#!/usr/bin/env bash
set -Eeuo pipefail

echo
echo "===== Kernel disk error summary ====="
if ! command -v dmesg >/dev/null 2>&1; then
  echo "dmesg bulunamadi."
  exit 0
fi

matches="$(dmesg -T 2>/dev/null | egrep -i 'ata[0-9].*(error|failed|reset)|I/O error|uncorrect|media and data integrity|nvme.*error|CRC' | tail -n 80 || true)"
if [[ -n "$matches" ]]; then
  echo "$matches"
  echo "Uyari: kernel disk hata sinyali var."
  exit 1
fi

echo "Kernel disk hata sinyali yakalanmadi."
