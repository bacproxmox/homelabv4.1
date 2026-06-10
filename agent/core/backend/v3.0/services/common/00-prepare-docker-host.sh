#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
STACKS_DIR="${STACKS_DIR:-/opt/homelab}"
DOCKER_NETWORK="${DOCKER_NETWORK:-homelab}"
apt-get update
apt-get install -y curl wget git nano jq unzip ca-certificates gnupg lsb-release nfs-common cifs-utils htop rsync uidmap
if ! command -v docker >/dev/null 2>&1; then curl -fsSL https://get.docker.com | sh; fi
systemctl enable --now docker
mkdir -p "$STACKS_DIR"
docker network create "$DOCKER_NETWORK" >/dev/null 2>&1 || true
if ! docker compose version >/dev/null 2>&1; then apt-get install -y docker-compose-plugin; fi
# standard dirs
mkdir -p /mnt/media /mnt/photos /mnt/private-photos /opt/homelab
systemctl daemon-reload
mount -a || true
