#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "homeassistant-service-install"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"
VM=105; WORK=/tmp/hv23-homeassistant; rm -rf "$WORK"; mkdir -p "$WORK"
source "$ROOT_DIR/utils/env-write.sh"
{
  write_env_header
  write_env_line TZ "${TZ:-Europe/Istanbul}"
} > "$WORK/.env"
cat > "$WORK/docker-compose.yml" <<'COMPOSE'
networks:
  homelab:
    external: true
services:
  homeassistant:
    image: ghcr.io/home-assistant/home-assistant:stable
    container_name: hb-homeassistant
    restart: unless-stopped
    networks: [homelab]
    privileged: true
    environment:
      - TZ=${TZ}
    volumes:
      - ./config:/config
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "8123:8123"
COMPOSE
cat > "$WORK/install.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
mkdir -p /opt/homelab/homeassistant/config
cp /tmp/hv23-homeassistant/docker-compose.yml /opt/homelab/homeassistant/docker-compose.yml
cp /tmp/hv23-homeassistant/.env /opt/homelab/homeassistant/.env
cd /opt/homelab/homeassistant
docker network create homelab >/dev/null 2>&1 || true
docker compose pull
docker compose up -d
REMOTE
chmod +x "$WORK/install.sh"
rscp "$WORK" "$VM" "/tmp/"
rssh "$VM" "sudo /tmp/hv23-homeassistant/install.sh"
