#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "adguard-home-additional-install"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"
source "$ROOT_DIR/utils/env-write.sh"
VM=103; WORK=/tmp/hv2313-adguard; rm -rf "$WORK"; mkdir -p "$WORK"
{
  write_env_header
  write_env_line TZ "${TZ:-Europe/Istanbul}"
} > "$WORK/.env"
cat > "$WORK/docker-compose.yml" <<'COMPOSE'
networks:
  homelab:
    external: true
services:
  adguard-home:
    image: adguard/adguardhome:latest
    container_name: hb-adguard-home
    restart: unless-stopped
    networks: [homelab]
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "3000:3000/tcp"
      - "8088:80/tcp"
    volumes:
      - ./work:/opt/adguardhome/work
      - ./conf:/opt/adguardhome/conf
COMPOSE
cat > "$WORK/install.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
mkdir -p /opt/homelab/adguard-home/work /opt/homelab/adguard-home/conf
cp /tmp/hv2313-adguard/docker-compose.yml /opt/homelab/adguard-home/docker-compose.yml
cp /tmp/hv2313-adguard/.env /opt/homelab/adguard-home/.env
cd /opt/homelab/adguard-home
docker network create homelab >/dev/null 2>&1 || true
if ss -lntup | grep -E ':(53)\b' >/dev/null 2>&1; then
  echo "⚠️ Port 53 halihazırda kullanımda olabilir. AdGuard DNS portu çakışabilir."
  ss -lntup | grep -E ':(53)\b' || true
fi
docker compose pull
docker compose up -d
cat <<MSG
✅ Optional AdGuard Home kuruldu.

İlk kurulum UI:
  http://192.168.50.103:3000

Kurulumdan sonra normal UI genelde:
  http://192.168.50.103:8088

Not:
  Core kurulumun parçası değildir. Router DNS'i 192.168.50.103'e yönlendirmeden önce UI'dan admin/upstream DNS ayarlarını tamamla.
MSG
REMOTE
chmod +x "$WORK/install.sh"
rscp "$WORK" "$VM" /tmp/
rssh "$VM" "sudo /tmp/hv2313-adguard/install.sh"
