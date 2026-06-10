#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "ollama-openwebui-models"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"

TMP="$(mktemp -d)"
cat > "$TMP/ollama-check.sh" <<'EOS'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /opt/homelab/ollama
docker compose up -d
for _ in $(seq 1 80); do docker exec hb-ollama ollama list >/dev/null 2>&1 && break; sleep 3; done
for model in "llama3.1:8b" "dolphin-mixtral:latest" "nomic-embed-text"; do
  if docker exec hb-ollama ollama list | awk '{print $1}' | grep -qx "$model"; then
    echo "✅ Model var: $model"
  else
    echo "▶️ Model indiriliyor: $model"
    docker exec hb-ollama ollama pull "$model" || echo "⚠️ Model indirilemedi: $model"
  fi
done
cat > /opt/homelab/ollama/OPENWEBUI_POLICY.txt <<'POLICY'
Homelab v2.3 Open WebUI policy:
- Required models:
  - llama3.1:8b
  - dolphin-mixtral:latest
  - nomic-embed-text
- Admin user target: admin@bacmastercloud.com
- Models should be visible to all Open WebUI users.
If Open WebUI API changes, verify from Admin Panel > Settings > Models.
POLICY
echo "✅ Open WebUI policy note yazıldı"
EOS
chmod +x "$TMP/ollama-check.sh"
rscp "$TMP/ollama-check.sh" 106 /tmp/hv23-ollama-check.sh
rssh 106 "sudo bash /tmp/hv23-ollama-check.sh"
rm -rf "$TMP"
