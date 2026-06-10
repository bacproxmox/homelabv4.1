#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "repair-nextcloud-data-storage"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"

echo "☁️ Nextcloud data storage repair: Docker volume app-code + TrueNAS tank data"

echo "1) TrueNAS Nextcloud dataset/NFS bootstrap doğrulanıyor..."
bash "$ROOT_DIR/services/truenas/01-truenas-api-bootstrap-storage.sh" || echo "⚠️ TrueNAS bootstrap hata verdi; mevcut share varsa VM104 preflight yine denenecek."

wait_ssh 104
rssh 104 'sudo bash -s' <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

mkdir -p /mnt/nextcloud/data /opt/homelab/nextcloud

if ! grep -qE '192\.168\.50\.101:/mnt/tank/nextcloud\s+/mnt/nextcloud\s+' /etc/fstab; then
  echo '192.168.50.101:/mnt/tank/nextcloud /mnt/nextcloud nfs defaults,_netdev,x-systemd.automount,nofail 0 0' >> /etc/fstab
fi
systemctl daemon-reload
mount /mnt/nextcloud || mount -a || true

if ! mountpoint -q /mnt/nextcloud; then
  echo "❌ /mnt/nextcloud mount değil. TrueNAS NFS share /mnt/tank/nextcloud kontrol et."
  exit 1
fi

mkdir -p /mnt/nextcloud/data
if ! chown 33:33 /mnt/nextcloud/data 2>/tmp/nc-chown.err; then
  echo "❌ /mnt/nextcloud/data chown 33:33 başarısız. TrueNAS NFS mapall/root veya dataset permission hatalı."
  cat /tmp/nc-chown.err || true
  exit 1
fi
chmod 750 /mnt/nextcloud/data || true

echo "✅ NFS preflight OK"
df -h /mnt/nextcloud /mnt/nextcloud/data || true

cd /opt/homelab/nextcloud
[[ -f .env ]] || cat > .env <<'ENV'
MYSQL_PASSWORD=nextcloudpass
MYSQL_ROOT_PASSWORD=nextcloudrootpass
MYSQL_DATABASE=nextcloud
MYSQL_USER=nextcloud
TZ=Europe/Istanbul
ENV

cat > docker-compose.yml <<'YAML'
volumes:
  nextcloud_html:
services:
  db:
    image: mariadb:11
    container_name: hb-nextcloud-db
    restart: unless-stopped
    command: --transaction-isolation=READ-COMMITTED --binlog-format=ROW
    environment:
      - MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
      - MYSQL_PASSWORD=${MYSQL_PASSWORD}
      - MYSQL_DATABASE=${MYSQL_DATABASE}
      - MYSQL_USER=${MYSQL_USER}
      - TZ=${TZ}
    volumes:
      - ./db:/var/lib/mysql
  redis:
    image: redis:7-alpine
    container_name: hb-nextcloud-redis
    restart: unless-stopped
  nextcloud:
    image: nextcloud:stable-apache
    container_name: hb-nextcloud
    restart: unless-stopped
    depends_on:
      - db
      - redis
    ports:
      - "8080:80"
    environment:
      - MYSQL_HOST=db
      - MYSQL_DATABASE=${MYSQL_DATABASE}
      - MYSQL_USER=${MYSQL_USER}
      - MYSQL_PASSWORD=${MYSQL_PASSWORD}
      - REDIS_HOST=redis
      - TZ=${TZ}
    volumes:
      - nextcloud_html:/var/www/html
      - /mnt/nextcloud/data:/var/www/html/data
YAML

docker compose down || true
docker compose up -d

for i in $(seq 1 90); do
  status="$(docker inspect -f '{{.State.Status}} {{.State.Restarting}}' hb-nextcloud 2>/dev/null || true)"
  if docker exec hb-nextcloud test -f /var/www/html/version.php >/dev/null 2>&1; then
    echo "✅ version.php OK"
    break
  fi
  if echo "$status" | grep -q 'true'; then
    echo "⚠️ hb-nextcloud restart loop görünüyor, log bekleniyor..."
    docker logs hb-nextcloud --tail=30 || true
  fi
  sleep 3
done

docker exec hb-nextcloud test -f /var/www/html/version.php || { docker logs hb-nextcloud --tail=120 || true; exit 1; }
docker exec hb-nextcloud df -h /var/www/html/data
REMOTE

echo "✅ Nextcloud data storage repair tamamlandı."
