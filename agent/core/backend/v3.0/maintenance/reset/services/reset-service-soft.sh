#!/usr/bin/env bash
set -Eeuo pipefail
SERVICE="${1:-}"
[[ -n "$SERVICE" ]] || { echo "Kullanım: $0 <service-name>"; exit 1; }
STACK="/opt/homelab/$SERVICE"
[[ -d "$STACK" ]] || { echo "❌ Stack yok: $STACK"; exit 1; }
echo "♻️ Soft reset: $SERVICE"
cd "$STACK"
docker compose down || true
docker compose up -d
echo "✅ Soft reset tamam."
