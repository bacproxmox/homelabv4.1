#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "uptime-kuma-service-install"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"
source "$ROOT_DIR/utils/env-write.sh"

VM=103
WORK=/tmp/hv2313-uptime-kuma
KUMA_IMAGE="${UPTIME_KUMA_IMAGE:-louislam/uptime-kuma:2.3.2}"

rm -rf "$WORK"; mkdir -p "$WORK"
{
  write_env_header
  write_env_line TZ "${TZ:-Europe/Istanbul}"
  write_env_line UPTIME_KUMA_IMAGE "$KUMA_IMAGE"
  write_env_line UPTIME_KUMA_DB_TYPE "sqlite"
} > "$WORK/.env"

cat > "$WORK/docker-compose.yml" <<'COMPOSE'
networks:
  homelab:
    external: true
services:
  uptime-kuma:
    image: ${UPTIME_KUMA_IMAGE}
    container_name: hb-uptime-kuma
    restart: unless-stopped
    networks: [homelab]
    environment:
      - TZ=${TZ}
      # v2 uses SQLite too; keep a conservative single-connection mode for small homelab boxes.
      - UPTIME_KUMA_DB_TYPE=${UPTIME_KUMA_DB_TYPE:-sqlite}
      - UPTIME_KUMA_SQLITE_SINGLE_CONNECTION=true
    volumes:
      - ./data:/app/data
    ports:
      - "3001:3001"
COMPOSE

cat > "$WORK/install.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
mkdir -p /opt/homelab/uptime-kuma/data /opt/homelab/backups/uptime-kuma
cp /tmp/hv2313-uptime-kuma/docker-compose.yml /opt/homelab/uptime-kuma/docker-compose.yml
cp /tmp/hv2313-uptime-kuma/.env /opt/homelab/uptime-kuma/.env
cd /opt/homelab/uptime-kuma

if docker ps -a --format '{{.Names}}' | grep -qx hb-uptime-kuma; then
  current_image="$(docker inspect -f '{{.Config.Image}}' hb-uptime-kuma 2>/dev/null || true)"
  echo "ℹ️ Mevcut Uptime Kuma image: ${current_image:-unknown}"
  if [[ -d data && -n "$(find data -mindepth 1 -maxdepth 2 -print -quit 2>/dev/null || true)" ]]; then
    backup="/opt/homelab/backups/uptime-kuma/data.pre-v2.4-$(date +%Y%m%d-%H%M%S).tar.gz"
    echo "🧷 Uptime Kuma data backup alınıyor: $backup"
    tar -czf "$backup" data
  fi
  docker compose down --remove-orphans || true
fi

docker network create homelab >/dev/null 2>&1 || true

echo "📦 Uptime Kuma image çekiliyor: ${UPTIME_KUMA_IMAGE:-louislam/uptime-kuma:2.3.2}"
docker compose pull

echo "🚀 Uptime Kuma v2 başlatılıyor..."
docker compose up -d

for i in $(seq 1 90); do
  if curl -fsS http://127.0.0.1:3001 >/dev/null 2>&1; then
    echo "✅ Uptime Kuma hazır: http://192.168.50.103:3001"
    docker exec hb-uptime-kuma node -e 'try{console.log("Uptime Kuma runtime OK")}catch(e){process.exit(0)}' 2>/dev/null || true
    exit 0
  fi
  if (( i % 10 == 0 )); then
    echo "⏳ Uptime Kuma bekleniyor... (${i}/90)"
    docker logs hb-uptime-kuma --tail=20 || true
  fi
  sleep 2
done

echo "❌ Uptime Kuma hazır olmadı. Son loglar:"
docker ps -a --filter name=hb-uptime-kuma || true
docker logs hb-uptime-kuma --tail=160 || true
exit 1
REMOTE
chmod +x "$WORK/install.sh"
rscp "$WORK" "$VM" "/tmp/"
rssh "$VM" "sudo /tmp/hv2313-uptime-kuma/install.sh"
