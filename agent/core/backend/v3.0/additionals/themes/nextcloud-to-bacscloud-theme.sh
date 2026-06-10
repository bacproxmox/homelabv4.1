#!/usr/bin/env bash
set -Eeuo pipefail
source /root/homelab-secrets/users.env
VM104_IP="192.168.50.104"; SSH_USER="${BACMASTER_USER:-bacmaster}"; SSH_PASS="${BACMASTER_PASS:?BACMASTER_PASS yok}"
apt update >/dev/null; apt install -y sshpass >/dev/null
sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_USER@$VM104_IP" 'sudo bash -s' <<'REMOTE'
set -Eeuo pipefail
cd /opt/homelab/nextcloud
NC_CONTAINER="$(docker ps --format '{{.Names}}' | grep -E '^(hb-nextcloud|nextcloud)$' | head -n1)"
occ(){ docker exec -u www-data "$NC_CONTAINER" php occ "$@"; }
occ app:enable theming || true
occ theming:config name "BacsCloud" || true
occ theming:config color "#1976d2" || true
docker restart "$NC_CONTAINER" >/dev/null || true
echo "✅ BacsCloud temel tema uygulandı."
REMOTE
