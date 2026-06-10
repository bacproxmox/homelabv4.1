#!/usr/bin/env bash
set -Eeuo pipefail
SERVICE="${1:-}"
[[ -n "$SERVICE" ]] || { echo "Kullanım: $0 <service-name>"; exit 1; }
STACK="/opt/homelab/$SERVICE"
[[ -d "$STACK" ]] || { echo "❌ Stack yok: $STACK"; exit 1; }
read -r -p "⚠️ $SERVICE container+volume/config silinecek. Emin misin? YES yaz: " ok
[[ "$ok" == "YES" ]] || exit 1
cd "$STACK"
docker compose down -v --remove-orphans || true
cd /opt/homelab
mv "$STACK" "$STACK.deleted.$(date +%Y%m%d-%H%M%S)"
echo "✅ Hard reset tamam."
