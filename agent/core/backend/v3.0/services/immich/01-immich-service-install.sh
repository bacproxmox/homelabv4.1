#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "immich-service-install"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"
VM=106; WORK=/tmp/hv244-immich; rm -rf "$WORK"; mkdir -p "$WORK"
IMMICH_DB_PASS="${IMMICH_DB_PASS:-$MEDIA_PASS}"
source "$ROOT_DIR/utils/env-write.sh"
{
  write_env_header
  write_env_line TZ "${TZ:-Europe/Istanbul}"
  write_env_line UPLOAD_LOCATION "/mnt/tank/photos/immich-upload"
  write_env_line DB_USERNAME "postgres"
  write_env_line DB_PASSWORD "$IMMICH_DB_PASS"
  write_env_line DB_DATABASE_NAME "immich"
  write_env_line IMMICH_VERSION "release"
} > "$WORK/.env"
cat > "$WORK/docker-compose.yml" <<'EOF_COMPOSE'
networks:
  homelab:
    external: true
services:
  immich-server:
    container_name: hb-immich-server
    image: ghcr.io/immich-app/immich-server:${IMMICH_VERSION:-release}
    restart: unless-stopped
    networks: [homelab]
    depends_on:
      - redis
      - database
    environment:
      - TZ=${TZ}
      - DB_HOSTNAME=database
      - DB_USERNAME=${DB_USERNAME}
      - DB_PASSWORD=${DB_PASSWORD}
      - DB_DATABASE_NAME=${DB_DATABASE_NAME}
      - REDIS_HOSTNAME=redis
    volumes:
      - ${UPLOAD_LOCATION}:/usr/src/app/upload
      - /mnt/tank/photos:/mnt/tank/photos:ro
      - /mnt/private/photos:/mnt/private/photos:ro
      - /etc/localtime:/etc/localtime:ro
    ports:
      - "2283:2283"
  immich-machine-learning:
    container_name: hb-immich-machine-learning
    image: ghcr.io/immich-app/immich-machine-learning:${IMMICH_VERSION:-release}
    restart: unless-stopped
    networks: [homelab]
    volumes:
      - ./model-cache:/cache
  redis:
    container_name: hb-immich-redis
    image: docker.io/redis:7-alpine
    restart: unless-stopped
    networks: [homelab]
  database:
    container_name: hb-immich-postgres
    image: ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0
    restart: unless-stopped
    networks: [homelab]
    environment:
      - POSTGRES_PASSWORD=${DB_PASSWORD}
      - POSTGRES_USER=${DB_USERNAME}
      - POSTGRES_DB=${DB_DATABASE_NAME}
      - POSTGRES_INITDB_ARGS=--data-checksums
    volumes:
      - ./postgres:/var/lib/postgresql/data
EOF_COMPOSE
cat > "$WORK/install.sh" <<'EOF_INSTALL'
#!/usr/bin/env bash
set -Eeuo pipefail
apt update >/dev/null
apt install -y nfs-common curl jq >/dev/null
mkdir -p /opt/homelab/immich /mnt/tank/photos /mnt/private/photos
for line in \
  '192.168.50.101:/mnt/tank/photos /mnt/tank/photos nfs defaults,_netdev,x-systemd.automount,nofail 0 0' \
  '192.168.50.101:/mnt/tank/private/photos /mnt/private/photos nfs defaults,_netdev,x-systemd.automount,nofail 0 0'
do
  dst="$(echo "$line" | awk '{print $2}')"
  grep -qs " $dst " /etc/fstab || echo "$line" >> /etc/fstab
done
systemctl daemon-reload
mount /mnt/tank/photos 2>/dev/null || true
mount /mnt/private/photos 2>/dev/null || true
mountpoint -q /mnt/tank/photos || { echo '❌ /mnt/tank/photos mount değil.'; exit 1; }
mountpoint -q /mnt/private/photos || { echo '❌ /mnt/private/photos mount değil.'; exit 1; }
mkdir -p /mnt/tank/photos/immich-upload
cp /tmp/hv244-immich/docker-compose.yml /opt/homelab/immich/docker-compose.yml
cp /tmp/hv244-immich/.env /opt/homelab/immich/.env
cd /opt/homelab/immich

docker network create homelab >/dev/null 2>&1 || true

# Optional GPU override: only add /dev/dri if device nodes actually exist.
if [[ -d /dev/dri && -e /dev/dri/renderD128 ]]; then
  echo "✅ /dev/dri bulundu; Immich GPU override etkinleştiriliyor."
  video_gid="$(getent group video | cut -d: -f3 || true)"
  render_gid="$(getent group render | cut -d: -f3 || true)"
  cat > docker-compose.gpu.yml <<GPUYAML
services:
  immich-server:
    devices:
      - /dev/dri:/dev/dri
    group_add:
GPUYAML
  [[ -n "$video_gid" ]] && echo "      - \"$video_gid\"" >> docker-compose.gpu.yml
  [[ -n "$render_gid" ]] && echo "      - \"$render_gid\"" >> docker-compose.gpu.yml
  compose_files=(-f docker-compose.yml -f docker-compose.gpu.yml)
else
  echo "⚠️ /dev/dri yok; Immich CPU mode ile başlatılacak. GPU acceleration daha sonra repair script ile etkinleştirilebilir."
  rm -f docker-compose.gpu.yml
  compose_files=(-f docker-compose.yml)
fi

docker compose "${compose_files[@]}" pull
docker compose "${compose_files[@]}" up -d

for i in {1..90}; do
  if curl -fsS http://127.0.0.1:2283/api/server/ping >/dev/null 2>&1 || curl -fsS http://127.0.0.1:2283/api/server/version >/dev/null 2>&1; then
    echo "✅ Immich API hazır: http://192.168.50.106:2283"
    exit 0
  fi
  if docker ps -a --format '{{.Names}} {{.Status}}' | grep -E '^hb-immich-server ' | grep -qiE 'Exited|Created'; then
    echo "⚠️ hb-immich-server henüz sağlıklı değil:"
    docker ps -a | grep immich || true
    docker logs hb-immich-server --tail=120 || true
  fi
  sleep 2
done

echo "❌ Immich API doğrulanamadı."
docker ps -a | grep immich || true
docker logs hb-immich-server --tail=200 || true
exit 1
EOF_INSTALL
chmod +x "$WORK/install.sh"
rscp "$WORK" "$VM" "/tmp/"
rssh "$VM" "sudo /tmp/hv244-immich/install.sh"
