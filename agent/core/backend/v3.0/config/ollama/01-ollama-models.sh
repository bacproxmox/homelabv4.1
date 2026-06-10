#!/usr/bin/env bash
set -Eeuo pipefail
set +H

echo
echo "🤖 Homelab v2.4.7 - Ollama Model Compatibility Helper"
echo

source /root/homelab-secrets/users.env
source /root/homelab-secrets/ollama-models.env 2>/dev/null || true

VM106_IP="192.168.50.106"
SSH_USER="${BACMASTER_USER:-bacmaster}"
SSH_PASS="${BACMASTER_PASS:?BACMASTER_PASS yok}"

OPENWEBUI_ADMIN_NAME="bacmaster"
OPENWEBUI_ADMIN_EMAIL="admin@bacmastercloud.com"
OPENWEBUI_ADMIN_PASS="${BACMASTER_PASS}"

if [[ "${OLLAMA_PULL_MODELS:-true}" != "true" ]]; then
  echo "ℹ️ Ollama model auto-config bootstrap'ta kapalı seçilmiş; script çıkıyor."
  exit 0
fi
read -r -a MODELS <<< "${OLLAMA_MODELS//,/ }"
if [[ "${#MODELS[@]}" -eq 0 ]]; then
  MODELS=("llama3.1:8b" "qwen2.5-coder:7b" "nomic-embed-text")
fi

apt update
apt install -y sshpass curl jq

shell_quote(){ printf "%q" "$1"; }

TMP="$(mktemp)"

cat > "$TMP" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
set +H

AI_DIR="/opt/homelab/ollama"
mkdir -p "$AI_DIR/config/ollama" "$AI_DIR/config/open-webui"
cd "$AI_DIR"

echo
echo "📦 Docker/Compose kontrol..."
command -v docker >/dev/null || { echo "❌ docker yok"; exit 1; }
docker compose version >/dev/null || { echo "❌ docker compose yok"; exit 1; }

if [[ ! -f docker-compose.yml ]]; then
  echo "❌ docker-compose.yml yok: $AI_DIR"
  exit 1
fi

echo
echo "🧩 docker-compose.yml içine Open WebUI garanti ekleniyor..."

if ! grep -q "container_name: hb-openwebui" docker-compose.yml; then
  cat >> docker-compose.yml <<'YAML'

  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: hb-openwebui
    restart: unless-stopped
    ports:
      - "3000:8080"
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
      - WEBUI_AUTH=True
      - ENABLE_SIGNUP=False
      - DEFAULT_USER_ROLE=user
      - WEBUI_NAME=Bacmaster AI
    volumes:
      - ./config/open-webui:/app/backend/data
    depends_on:
      - ollama
YAML
  echo "✅ Open WebUI eklendi."
else
  echo "✅ Open WebUI zaten compose içinde."
fi

echo
echo "🚀 Ollama + Open WebUI başlatılıyor..."
docker compose up -d ollama open-webui

echo
echo "⏳ Ollama API bekleniyor..."
for i in {1..90}; do
  if curl -fsS http://127.0.0.1:11434/api/tags >/tmp/ollama-tags.json 2>/dev/null; then
    echo "✅ Ollama API hazır."
    break
  fi
  sleep 2
done

if ! curl -fsS http://127.0.0.1:11434/api/tags >/tmp/ollama-tags.json 2>/dev/null; then
  echo "❌ Ollama API cevap vermiyor."
  docker logs hb-ollama --tail=120 || true
  exit 1
fi

echo
echo "📋 Mevcut modeller:"
cat /tmp/ollama-tags.json | jq -r '.models[]?.name' || true

echo
echo "📥 Eksik modeller indiriliyor... (v2.4: normal kullanımda additionals/ai menüsünü tercih et)"

for model in $OLLAMA_MODELS; do
  base="${model%:latest}"
  if cat /tmp/ollama-tags.json | jq -r '.models[]?.name' | grep -Eq "^${model}$|^${base}:latest$|^${base}$"; then
    echo "✅ Model var: $model"
  else
    echo "⬇️ Model indiriliyor: $model"
    docker exec hb-ollama ollama pull "$model"
  fi
done

echo
echo "🧪 Test inference..."
TEST_MODEL="$(echo "$OLLAMA_MODELS" | awk '{print $1}')"

RESP="$(curl -fsS http://127.0.0.1:11434/api/generate \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"$TEST_MODEL\",\"prompt\":\"Sadece OK yaz.\",\"stream\":false}" \
  | jq -r '.response' || true)"

echo "Model cevabı: $RESP"

echo
echo "🌐 Open WebUI kontrol..."
for i in {1..60}; do
  CODE="$(curl -sS -o /tmp/openwebui.html -w "%{http_code}" http://127.0.0.1:3000 || true)"
  if [[ "$CODE" == "200" || "$CODE" == "302" ]]; then
    echo "✅ Open WebUI hazır. HTTP: $CODE"
    break
  fi
  sleep 2
done

echo
echo "👤 Admin bilgileri:"
echo "  Kullanıcı: $OPENWEBUI_ADMIN_NAME"
echo "  Email: $OPENWEBUI_ADMIN_EMAIL"
echo "  Şifre: BACMASTER_PASS"
echo
echo "Not: Open WebUI ilk açılışta ilk kullanıcıyı owner/admin yapar."
echo "URL: http://192.168.50.106:3000"

echo
echo "📋 Final container durumu:"
docker compose ps ollama open-webui

echo
echo "✅ Ollama yapılandırması tamamlandı."
REMOTE

MODEL_STRING="${MODELS[*]}"

sshpass -p "$SSH_PASS" scp \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  "$TMP" "$SSH_USER@$VM106_IP:/tmp/configure-ollama.sh" >/dev/null

sshpass -p "$SSH_PASS" ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  "$SSH_USER@$VM106_IP" \
  "printf '%s\n' $(shell_quote "$SSH_PASS") | sudo -S -p '' env \
OLLAMA_MODELS=$(shell_quote "$MODEL_STRING") \
OPENWEBUI_ADMIN_NAME=$(shell_quote "$OPENWEBUI_ADMIN_NAME") \
OPENWEBUI_ADMIN_EMAIL=$(shell_quote "$OPENWEBUI_ADMIN_EMAIL") \
OPENWEBUI_ADMIN_PASS=$(shell_quote "$OPENWEBUI_ADMIN_PASS") \
bash /tmp/configure-ollama.sh"

rm -f "$TMP"

echo
echo "✅ config/ollama/01-ollama-models.sh tamamlandı."
echo "Kontrol:"
echo "  Ollama API:  http://192.168.50.106:11434/api/tags"
echo "  Open WebUI:  http://192.168.50.106:3000"
