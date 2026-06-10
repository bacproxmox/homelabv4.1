#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "lidarr-service-install"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"
VM=106; WORK=/tmp/hv23-lidarr; rm -rf "$WORK"; mkdir -p "$WORK"
source "$ROOT_DIR/utils/env-write.sh"
{
  write_env_header
  write_env_line TZ "${TZ:-Europe/Istanbul}"
  write_env_line PUID "${MEDIA_UID:-1000}"
  write_env_line PGID "${MEDIA_GID:-1000}"
} > "$WORK/.env"
cat > "$WORK/docker-compose.yml" <<'EOF'
networks:
  homelab:
    external: true
services:
  lidarr:
    image: lscr.io/linuxserver/lidarr:latest
    container_name: hb-lidarr
    restart: unless-stopped
    networks: [homelab]
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ./config/lidarr:/config
      - /mnt/media:/media
      - /mnt/media/downloads:/downloads
    ports:
      - "8686:8686"
EOF
cat > "$WORK/install.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
mkdir -p /opt/homelab/lidarr/config/lidarr /mnt/media/music /mnt/media/downloads
cp /tmp/hv23-lidarr/docker-compose.yml /opt/homelab/lidarr/docker-compose.yml
cp /tmp/hv23-lidarr/.env /opt/homelab/lidarr/.env
cd /opt/homelab/lidarr
docker network create homelab >/dev/null 2>&1 || true
docker compose pull
docker compose up -d
EOF
chmod +x "$WORK/install.sh"
rscp "$WORK" "$VM" "/tmp/"
rssh "$VM" "sudo /tmp/hv23-lidarr/install.sh"
