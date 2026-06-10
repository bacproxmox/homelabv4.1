#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "arr-service-install"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"
VM=102; STACK="arr"; WORK="/tmp/hv23-$STACK"; rm -rf "$WORK"; mkdir -p "$WORK"
source "$ROOT_DIR/utils/env-write.sh"
{
  write_env_header
  write_env_line TZ "${TZ:-Europe/Istanbul}"
  write_env_line PUID "${MEDIA_UID:-1000}"
  write_env_line PGID "${MEDIA_GID:-1000}"
  write_env_line ARR_USER "${ARR_USER:-bacmaster}"
  write_env_line ARR_PASS "${ARR_PASS:-${BACMASTER_PASS:-}}"
} > "$WORK/.env"
cat > "$WORK/docker-compose.yml" <<'EOF'
networks:
  homelab:
    external: true
services:
  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: hb-qbittorrent
    restart: unless-stopped
    networks: [homelab]
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
      - WEBUI_PORT=8080
    volumes:
      - ./config/qbittorrent:/config
      - /mnt/media/downloads:/downloads
      - /mnt/media:/media
    ports:
      - "8080:8080"
      - "6881:6881"
      - "6881:6881/udp"
  flaresolverr:
    image: ghcr.io/flaresolverr/flaresolverr:latest
    container_name: hb-flaresolverr
    restart: unless-stopped
    networks: [homelab]
    environment:
      - LOG_LEVEL=info
      - TZ=${TZ}
    ports:
      - "8191:8191"
  prowlarr:
    image: lscr.io/linuxserver/prowlarr:latest
    container_name: hb-prowlarr
    restart: unless-stopped
    networks: [homelab]
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ./config/prowlarr:/config
    ports:
      - "9696:9696"
  sonarr:
    image: lscr.io/linuxserver/sonarr:latest
    container_name: hb-sonarr
    restart: unless-stopped
    networks: [homelab]
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ./config/sonarr:/config
      - /mnt/media:/media
      - /mnt/media/downloads:/downloads
    ports:
      - "8989:8989"
  radarr:
    image: lscr.io/linuxserver/radarr:latest
    container_name: hb-radarr
    restart: unless-stopped
    networks: [homelab]
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ./config/radarr:/config
      - /mnt/media:/media
      - /mnt/media/downloads:/downloads
    ports:
      - "7878:7878"
  bazarr:
    image: lscr.io/linuxserver/bazarr:latest
    container_name: hb-bazarr
    restart: unless-stopped
    networks: [homelab]
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ./config/bazarr:/config
      - /mnt/media:/media
    ports:
      - "6767:6767"
EOF
cat > "$WORK/install.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
mkdir -p /opt/homelab/arr/config /mnt/media/downloads/torrents /mnt/media/movies /mnt/media/series
cp /tmp/hv23-arr/docker-compose.yml /opt/homelab/arr/docker-compose.yml
cp /tmp/hv23-arr/.env /opt/homelab/arr/.env
cd /opt/homelab/arr
docker network create homelab >/dev/null 2>&1 || true
docker compose pull
docker compose up -d
EOF
chmod +x "$WORK/install.sh"
rscp "$WORK" "$VM" "/tmp/"
rssh "$VM" "sudo /tmp/hv23-arr/install.sh"
