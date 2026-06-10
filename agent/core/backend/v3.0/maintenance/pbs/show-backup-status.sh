#!/usr/bin/env bash
set -Eeuo pipefail
echo "===== PVE PBS storage ====="
pvesm status | grep -E 'pbs|Name' || true
echo
echo "===== PVE backup jobs ====="
pvesh get /cluster/backup 2>/dev/null || true
echo
echo "===== PBS reachability ====="
curl -k -I --connect-timeout 5 --max-time 10 https://192.168.50.110:8007 || true
