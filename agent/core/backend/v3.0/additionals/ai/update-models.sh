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

ssh_ollama 'set -Eeuo pipefail; for m in $(docker exec hb-ollama ollama list | awk "NR>1 {print \$1}"); do echo "⬇️ Updating $m"; docker exec hb-ollama ollama pull "$m"; done'
