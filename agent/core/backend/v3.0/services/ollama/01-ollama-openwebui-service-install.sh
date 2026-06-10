#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "ollama-openwebui-install"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"
source "$ROOT_DIR/utils/env-write.sh"
VM=106
WORK=/tmp/hv2313-ollama
rm -rf "$WORK"; mkdir -p "$WORK"
WEBUI_SECRET_KEY="$(openssl rand -hex 32 2>/dev/null || date +%s%N)"
{
  write_env_header
  write_env_line TZ "${TZ:-Europe/Istanbul}"
  write_env_line WEBUI_SECRET_KEY "$WEBUI_SECRET_KEY"
  write_env_line OPENWEBUI_ADMIN_EMAIL "${OPENWEBUI_ADMIN_EMAIL:-admin@bacmastercloud.com}"
  write_env_line OPENWEBUI_ADMIN_PASS "${OPENWEBUI_ADMIN_PASS:-${BACMASTER_PASS:-}}"
  write_env_line OLLAMA_PULL_MODELS "${OLLAMA_PULL_MODELS:-false}"
  write_env_line OLLAMA_MODELS "${OLLAMA_MODELS:-}"
} > "$WORK/.env"
cat > "$WORK/install.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
mkdir -p /opt/homelab/ollama/ollama /opt/homelab/ollama/open-webui /mnt/ollama
if grep -q "/mnt/ollama " /etc/fstab; then
  systemctl daemon-reload || true
  mount /mnt/ollama || mount -a || true
fi
OLLAMA_VOLUME="./ollama:/root/.ollama"
if mountpoint -q /mnt/ollama; then
  mkdir -p /mnt/ollama/models
  chown -R 1000:1000 /mnt/ollama 2>/dev/null || true
  OLLAMA_VOLUME="/mnt/ollama:/root/.ollama"
  echo "Ollama tank model library mounted: /mnt/ollama"
else
  echo "Ollama tank mount not available; using local VM storage."
fi
chown -R 1000:1000 /opt/homelab/ollama 2>/dev/null || true
cp /tmp/hv2313-ollama/.env /opt/homelab/ollama/.env
cd /opt/homelab/ollama
GPU_BLOCK=""
if [[ -d /dev/dri && -e /dev/dri/renderD128 ]]; then
  echo "✅ /dev/dri bulundu. Ollama container'a iGPU device eklenecek."
  GPU_BLOCK='    devices:
      - /dev/dri:/dev/dri
    group_add:
      - "44"
      - "109"'
else
  echo "⚠️ /dev/dri yok. Ollama/Open WebUI GPU device olmadan kurulacak."
fi
cat > docker-compose.yml <<EOFYAML
networks:
  homelab:
    external: true
services:
  ollama:
    image: ollama/ollama:latest
    container_name: hb-ollama
    restart: unless-stopped
    networks: [homelab]
    environment:
      - TZ=\${TZ}
    volumes:
      - ${OLLAMA_VOLUME}
    ports:
      - "11434:11434"
${GPU_BLOCK}
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: hb-openwebui
    restart: unless-stopped
    networks: [homelab]
    depends_on:
      - ollama
    environment:
      - TZ=\${TZ}
      - OLLAMA_BASE_URL=http://ollama:11434
      - WEBUI_SECRET_KEY=\${WEBUI_SECRET_KEY}
      - ENABLE_SIGNUP=true
    volumes:
      - ./open-webui:/app/backend/data
    ports:
      - "3000:8080"
EOFYAML
python3 - <<'PY'
from pathlib import Path
p=Path('docker-compose.yml')
s=p.read_text().replace('\n\n  open-webui:', '\n  open-webui:')
p.write_text(s)
PY
docker network create homelab >/dev/null 2>&1 || true
docker compose pull
docker compose up -d

if [[ "${OLLAMA_PULL_MODELS:-false}" == "true" && -n "${OLLAMA_MODELS:-}" ]]; then
  echo "⏳ Ollama API bekleniyor..."
  for i in {1..120}; do
    curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && break
    sleep 2
  done
  echo "📥 Bootstrap aşamasında seçilen Ollama modelleri indiriliyor: ${OLLAMA_MODELS}"
  for model in ${OLLAMA_MODELS//,/ }; do
    [[ -n "$model" ]] || continue
    echo "⬇️ ollama pull $model"
    docker exec hb-ollama ollama pull "$model" || echo "⚠️ Model indirilemedi: $model"
  done
else
  echo "ℹ️ Ollama model auto-pull kapalı veya model listesi boş."
fi
cat <<MSG
✅ Ollama/Open WebUI kuruldu.
Model yönetimi için: Additionals menu > AI / Ollama model management
MSG
REMOTE
chmod +x "$WORK/install.sh"
rscp "$WORK" "$VM" "/tmp/"
rssh "$VM" "sudo /tmp/hv2313-ollama/install.sh"
