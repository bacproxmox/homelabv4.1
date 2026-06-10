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
cat <<'MODELS'
Örnek modeller:
  llama3.1:8b              ~4-5GB
  nomic-embed-text:latest  embedding modeli
  dolphin-mixtral:latest   büyük model, ~26GB+
  qwen2.5:7b
  gemma3:4b
  deepseek-r1:8b
MODELS
read -r -p "Kurulacak model adı: " MODEL
[[ -n "$MODEL" ]] || exit 0
BASE="${MODEL%:latest}"
ssh_ollama "set -Eeuo pipefail; INST=\$(docker exec hb-ollama ollama list | awk 'NR>1 {print \$1}'); if echo \"\$INST\" | grep -Eq '(^${MODEL}$)|(^${BASE}:latest$)|(^${BASE}$)'; then echo '✅ Model zaten var: ${MODEL}'; else docker exec hb-ollama ollama pull '${MODEL}'; fi"
