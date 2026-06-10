#!/usr/bin/env bash
set -Eeuo pipefail
VMID="${1:-}"
[[ -n "$VMID" ]] || { echo "Kullanım: $0 <vmid>"; exit 1; }
read -r -p "⚠️ VM $VMID tamamen silinecek. Emin misin? YES yaz: " ok
[[ "$ok" == "YES" ]] || exit 1
qm stop "$VMID" 2>/dev/null || true
qm destroy "$VMID" --purge 2>/dev/null || true
echo "✅ VM $VMID silindi."
