#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "seerr-service-install"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"
VM=102; WORK=/tmp/hv2313-seerr; rm -rf "$WORK"; mkdir -p "$WORK"
source "$ROOT_DIR/utils/env-write.sh"
{
  write_env_header
  write_env_line TZ "${TZ:-Europe/Istanbul}"
} > "$WORK/.env"
cat > "$WORK/docker-compose.yml" <<'EOF'
networks:
  homelab:
    external: true
services:
  seerr:
    image: ghcr.io/seerr-team/seerr:latest
    container_name: hb-seerr
    init: true
    restart: unless-stopped
    networks: [homelab]
    environment:
      - LOG_LEVEL=info
      - TZ=${TZ}
    volumes:
      - ./config:/app/config
    ports:
      - "5055:5055"
EOF
cat > "$WORK/install.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
mkdir -p /opt/homelab/seerr/config/logs
chown -R 1000:1000 /opt/homelab/seerr
chmod -R 775 /opt/homelab/seerr
cp /tmp/hv2313-seerr/docker-compose.yml /opt/homelab/seerr/docker-compose.yml
cp /tmp/hv2313-seerr/.env /opt/homelab/seerr/.env
cd /opt/homelab/seerr
docker network create homelab >/dev/null 2>&1 || true
docker compose pull
docker compose up -d
EOF
chmod +x "$WORK/install.sh"
rscp "$WORK" "$VM" "/tmp/"
rssh "$VM" "sudo /tmp/hv2313-seerr/install.sh"
