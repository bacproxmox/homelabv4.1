#!/usr/bin/env bash
set -Eeuo pipefail
set +H

echo "🧠 Homelab v2.4.7 - Open WebUI Admin Fix"

source /root/homelab-secrets/users.env

VM106_IP="192.168.50.106"
SSH_USER="${BACMASTER_USER:-bacmaster}"
SSH_PASS="${BACMASTER_PASS:?BACMASTER_PASS yok}"

apt update
apt install -y sshpass

shell_quote(){ printf "%q" "$1"; }

TMP="$(mktemp)"

cat > "$TMP" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
set +H

AI_DIR="/opt/homelab/ollama"
cd "$AI_DIR"

echo "🧹 Open WebUI resetleniyor..."
docker compose stop open-webui || true
docker compose rm -f open-webui || true

STAMP="$(date +%Y%m%d-%H%M%S)"
if [[ -d config/open-webui ]]; then
  mv config/open-webui "config/open-webui.broken.$STAMP"
fi

mkdir -p config/open-webui
chown -R 1000:1000 config/open-webui || true

echo "📝 Compose admin env güncelleniyor..."

python3 - <<PY
from pathlib import Path

p = Path("docker-compose.yml")
text = p.read_text()

env_lines = [
"      - WEBUI_AUTH=True",
"      - ENABLE_SIGNUP=False",
"      - DEFAULT_USER_ROLE=user",
"      - WEBUI_NAME=Bacmaster AI",
"      - WEBUI_ADMIN_NAME=bacmaster",
"      - WEBUI_ADMIN_EMAIL=admin@bacmastercloud.com",
"      - WEBUI_ADMIN_PASSWORD=${BACMASTER_PASS}",
]

# Eğer open-webui yoksa ekle
if "container_name: hb-openwebui" not in text:
    text += """

  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: hb-openwebui
    restart: unless-stopped
    ports:
      - "3000:8080"
    environment:
""" + "\n".join(env_lines) + """
      - OLLAMA_BASE_URL=http://ollama:11434
    volumes:
      - ./config/open-webui:/app/backend/data
    depends_on:
      - ollama
"""
else:
    # Basit ve güvenli: open-webui environment satırlarının duplicate olmaması için eski admin/auth satırlarını temizle
    remove_keys = [
        "WEBUI_AUTH=", "ENABLE_SIGNUP=", "DEFAULT_USER_ROLE=", "WEBUI_NAME=",
        "WEBUI_ADMIN_NAME=", "WEBUI_ADMIN_EMAIL=", "WEBUI_ADMIN_PASSWORD=",
    ]
    lines = []
    for line in text.splitlines():
        if any(k in line for k in remove_keys):
            continue
        lines.append(line)
    text = "\n".join(lines) + "\n"

    marker = "      - OLLAMA_BASE_URL=http://ollama:11434"
    if marker in text:
        text = text.replace(marker, "\n".join(env_lines) + "\n" + marker)
    else:
        text = text.replace("    environment:\n", "    environment:\n" + "\n".join(env_lines) + "\n", 1)

p.write_text(text)
PY

docker compose config >/dev/null

echo "🚀 Open WebUI başlatılıyor..."
docker compose up -d ollama open-webui

echo "⏳ Open WebUI bekleniyor..."
for i in {1..90}; do
  CODE="$(curl -sS -o /tmp/owui.html -w "%{http_code}" http://127.0.0.1:3000 || true)"
  if [[ "$CODE" == "200" || "$CODE" == "302" ]]; then
    echo "✅ Open WebUI hazır. HTTP: $CODE"
    break
  fi
  sleep 2
done

echo
echo "📋 Container:"
docker compose ps open-webui

echo
echo "✅ Admin otomatik oluşturma ayarı tamam."
echo "URL: http://192.168.50.106:3000"
echo "Login:"
echo "  admin@bacmastercloud.com"
echo "  BACMASTER_PASS"
REMOTE

sshpass -p "$SSH_PASS" scp \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  "$TMP" "$SSH_USER@$VM106_IP:/tmp/fix-openwebui.sh" >/dev/null

sshpass -p "$SSH_PASS" ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  "$SSH_USER@$VM106_IP" \
  "printf '%s\n' $(shell_quote "$SSH_PASS") | sudo -S -p '' env BACMASTER_PASS=$(shell_quote "$SSH_PASS") bash /tmp/fix-openwebui.sh"

rm -f "$TMP"

echo "✅ config/ollama/02-fix-openwebui-admin.sh tamamlandı."
