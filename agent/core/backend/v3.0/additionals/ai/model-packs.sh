#!/usr/bin/env bash
set -Eeuo pipefail
VM106_IP="192.168.50.106"
SECRETS_DIR="/root/homelab-secrets"
source "$SECRETS_DIR/users.env"
SSH_USER="${BACMASTER_USER:-bacmaster}"
SSH_PASS="${BACMASTER_PASS:?BACMASTER_PASS yok}"
apt update >/dev/null
apt install -y sshpass >/dev/null
ssh_ollama(){ sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USER@$VM106_IP" "$@"; }
PACK="${1:-}"
case "$PACK" in
  lightweight) MODELS=("gemma3:4b" "nomic-embed-text:latest") ;;
  general) MODELS=("llama3.1:8b" "nomic-embed-text:latest") ;;
  developer) MODELS=("qwen2.5:7b" "deepseek-r1:8b" "nomic-embed-text:latest") ;;
  *) echo "Kullanım: $0 [lightweight|general|developer]"; exit 1 ;;
esac
for MODEL in "${MODELS[@]}"; do
  BASE="${MODEL%:latest}"
  echo "➡️ $MODEL"
  ssh_ollama "set -Eeuo pipefail; INST=\$(docker exec hb-ollama ollama list | awk 'NR>1 {print \$1}'); if echo \"\$INST\" | grep -Eq '(^${MODEL}$)|(^${BASE}:latest$)|(^${BASE}$)'; then echo '✅ Model zaten var: ${MODEL}'; else docker exec hb-ollama ollama pull '${MODEL}'; fi"
done
