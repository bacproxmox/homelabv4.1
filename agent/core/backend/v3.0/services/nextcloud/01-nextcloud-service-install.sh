#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "nextcloud-service-install"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"
source "$ROOT_DIR/utils/env-write.sh"

VM=104
WORK=/tmp/hv2313-nextcloud
TN_API="http://${TRUENAS_IP:-192.168.50.101}/api/v2.0"

prepare_truenas_nextcloud_permissions() {
  if [[ -z "${TRUENAS_API_KEY:-}" ]]; then
    echo "⚠️ TRUENAS_API_KEY yok; Nextcloud NFS permission otomatik düzeltmesi atlandı."
    echo "   VM104 preflight chown başarısız olursa önce services/truenas/01-truenas-api-bootstrap-storage.sh çalıştır."
    return 0
  fi

  echo "🧊 TrueNAS Nextcloud dataset/NFS permission preflight..."

  tn_get() {
    curl -sk --connect-timeout 8 --max-time 30 \
      -H "Authorization: Bearer ${TRUENAS_API_KEY}" \
      "$TN_API/$1"
  }
  tn_post() {
    curl -sk --connect-timeout 8 --max-time 30 \
      -X POST \
      -H "Authorization: Bearer ${TRUENAS_API_KEY}" \
      -H "Content-Type: application/json" \
      -d "$2" \
      "$TN_API/$1"
  }
  tn_put() {
    curl -sk --connect-timeout 8 --max-time 30 \
      -X PUT \
      -H "Authorization: Bearer ${TRUENAS_API_KEY}" \
      -H "Content-Type: application/json" \
      -d "$2" \
      "$TN_API/$1"
  }

  tn_get "system/info" >/tmp/hv2313-truenas-info.json || {
    echo "⚠️ TrueNAS API erişimi başarısız; VM104 NFS preflight ile devam edilecek."
    return 0
  }

  for ds in tank/nextcloud tank/nextcloud/data; do
    tn_post "pool/dataset" "{\"name\":\"${ds}\",\"share_type\":\"GENERIC\"}" >/dev/null || true
  done
  tn_post "filesystem/mkdir" '{"path":"/mnt/tank/nextcloud/data"}' >/dev/null || true

  # Official Nextcloud container needs www-data ownership for /var/www/html/data.
  for path in /mnt/tank/nextcloud /mnt/tank/nextcloud/data; do
    echo "🔐 TrueNAS permission: $path => 33:33"
    tn_post "filesystem/chown" "{\"path\":\"${path}\",\"uid\":33,\"gid\":33,\"options\":{\"recursive\":true,\"traverse\":true}}" >/dev/null || true
  done
  tn_post "filesystem/setperm" '{"path":"/mnt/tank/nextcloud","mode":"775","uid":33,"gid":33,"options":{"recursive":true,"traverse":true}}' >/dev/null || true
  tn_post "filesystem/setperm" '{"path":"/mnt/tank/nextcloud/data","mode":"750","uid":33,"gid":33,"options":{"recursive":true,"traverse":true}}' >/dev/null || true

  tn_get "sharing/nfs" >/tmp/hv2313-truenas-nfs.json || echo "[]" >/tmp/hv2313-truenas-nfs.json
  nfs_id="$(python3 - <<'PY'
import json
from pathlib import Path
try:
    data=json.loads(Path('/tmp/hv2313-truenas-nfs.json').read_text() or '[]')
except Exception:
    data=[]
for item in data:
    paths=item.get('paths') or []
    path=item.get('path')
    if path == '/mnt/tank/nextcloud' or '/mnt/tank/nextcloud' in paths:
        print(item.get('id',''))
        break
PY
)"
  payload='{"path":"/mnt/tank/nextcloud","comment":"Nextcloud user data NFS","enabled":true,"networks":["192.168.50.0/24"],"maproot_user":"","maproot_group":"","mapall_user":"root","mapall_group":"root","ro":false}'
  if [[ -n "$nfs_id" ]]; then
    echo "📡 TrueNAS NFS update: /mnt/tank/nextcloud mapall=root/root"
    tn_put "sharing/nfs/id/${nfs_id}" "$payload" >/dev/null || true
  else
    echo "📡 TrueNAS NFS create: /mnt/tank/nextcloud mapall=root/root"
    tn_post "sharing/nfs" "$payload" >/dev/null || true
  fi
  tn_post "service/restart" '{"service":"nfs"}' >/dev/null || true
  sleep 3
}

prepare_truenas_nextcloud_permissions

rm -rf "$WORK"; mkdir -p "$WORK"
{
  write_env_header
  write_env_line TZ "${TZ:-Europe/Istanbul}"
  write_env_line MYSQL_PASSWORD "${NEXTCLOUD_DB_PASS:-${MEDIA_PASS:-}}"
  write_env_line MYSQL_DATABASE "nextcloud"
  write_env_line MYSQL_USER "nextcloud"
  write_env_line MYSQL_ROOT_PASSWORD "${NEXTCLOUD_DB_PASS:-${MEDIA_PASS:-}}"
  write_env_line NEXTCLOUD_ADMIN_USER "${NEXTCLOUD_ADMIN_USER:-bacmaster}"
  write_env_line NEXTCLOUD_ADMIN_PASSWORD "${NEXTCLOUD_ADMIN_PASS:-${BACMASTER_PASS:-}}"
  write_env_line NEXTCLOUD_TRUSTED_DOMAINS "192.168.50.104 cloud.bacmastercloud.com cloud-api.bacmastercloud.com"
  write_env_line OVERWRITECLIURL "http://192.168.50.104:8080"
} > "$WORK/.env"

cat > "$WORK/docker-compose.yml" <<'EOFYAML'
networks:
  homelab:
    external: true
volumes:
  nextcloud_html:
services:
  db:
    image: mariadb:11
    container_name: hb-nextcloud-db
    restart: unless-stopped
    networks: [homelab]
    command: --transaction-isolation=READ-COMMITTED --binlog-format=ROW
    environment:
      - MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}
      - MYSQL_PASSWORD=${MYSQL_PASSWORD}
      - MYSQL_DATABASE=${MYSQL_DATABASE}
      - MYSQL_USER=${MYSQL_USER}
    volumes:
      - ./db:/var/lib/mysql
  redis:
    image: redis:7-alpine
    container_name: hb-nextcloud-redis
    restart: unless-stopped
    networks: [homelab]
  app:
    image: nextcloud:stable-apache
    container_name: hb-nextcloud
    restart: unless-stopped
    networks: [homelab]
    depends_on:
      - db
      - redis
    ports:
      - "8080:80"
    environment:
      - MYSQL_HOST=db
      - MYSQL_PASSWORD=${MYSQL_PASSWORD}
      - MYSQL_DATABASE=${MYSQL_DATABASE}
      - MYSQL_USER=${MYSQL_USER}
      - NEXTCLOUD_ADMIN_USER=${NEXTCLOUD_ADMIN_USER}
      - NEXTCLOUD_ADMIN_PASSWORD=${NEXTCLOUD_ADMIN_PASSWORD}
      - NEXTCLOUD_TRUSTED_DOMAINS=${NEXTCLOUD_TRUSTED_DOMAINS}
      - REDIS_HOST=redis
      - OVERWRITECLIURL=${OVERWRITECLIURL}
    volumes:
      - nextcloud_html:/var/www/html
      - /mnt/nextcloud/data:/var/www/html/data
      - /mnt/private-documents:/mnt/private-documents
EOFYAML

cat > "$WORK/install.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update >/dev/null
apt-get install -y nfs-common jq >/dev/null
mkdir -p /opt/homelab/nextcloud /mnt/nextcloud /mnt/private-documents
if ! grep -qsE '^192\.168\.50\.101:/mnt/tank/nextcloud\s+/mnt/nextcloud\s+' /etc/fstab; then
  echo '192.168.50.101:/mnt/tank/nextcloud /mnt/nextcloud nfs defaults,_netdev,x-systemd.automount,nofail 0 0' >> /etc/fstab
fi
if ! grep -qsE '^192\.168\.50\.101:/mnt/tank/private/documents\s+/mnt/private-documents\s+' /etc/fstab; then
  echo '192.168.50.101:/mnt/tank/private/documents /mnt/private-documents nfs defaults,_netdev,x-systemd.automount,nofail 0 0' >> /etc/fstab
fi
systemctl daemon-reload
mount /mnt/nextcloud 2>/dev/null || mount -a || true
mount /mnt/private-documents 2>/dev/null || true

if ! mountpoint -q /mnt/nextcloud; then
  echo '❌ /mnt/nextcloud mount değil. Önce TrueNAS API bootstrap ile /mnt/tank/nextcloud NFS share oluştur.'
  exit 1
fi

mkdir -p /mnt/nextcloud/data

echo '🧪 Nextcloud NFS permission preflight: chown/chmod test...'
if ! sudo chown -R 33:33 /mnt/nextcloud/data; then
  cat <<'ERR'
❌ /mnt/nextcloud/data üzerinde chown 33:33 başarısız.

Muhtemel sebep:
  TrueNAS NFS share /mnt/tank/nextcloud root chown'a izin vermiyor.

Çözüm:
  1) Proxmox host üzerinde tekrar çalıştır:
     bash services/truenas/01-truenas-api-bootstrap-storage.sh
  2) TrueNAS UI kontrol:
     Dataset tank/nextcloud ve tank/nextcloud/data owner: www-data:www-data veya UID/GID 33:33
     NFS /mnt/tank/nextcloud Maproot User: root, Maproot Group: root
  3) Sonra bu Nextcloud service install scriptini tekrar çalıştır.
ERR
  exit 23
fi
if ! sudo chmod -R 750 /mnt/nextcloud/data; then
  echo '❌ /mnt/nextcloud/data chmod başarısız. TrueNAS ACL/NFS izinlerini kontrol et.'
  exit 24
fi

cp /tmp/hv2313-nextcloud/docker-compose.yml /opt/homelab/nextcloud/docker-compose.yml
cp /tmp/hv2313-nextcloud/.env /opt/homelab/nextcloud/.env
cd /opt/homelab/nextcloud
docker network create homelab >/dev/null 2>&1 || true

docker compose down --remove-orphans || true
docker compose pull
docker compose up -d

echo '⏳ Nextcloud container readiness bekleniyor...'
for i in $(seq 1 120); do
  status="$(docker inspect -f '{{.State.Status}} {{.State.Restarting}}' hb-nextcloud 2>/dev/null || true)"
  if echo "$status" | grep -q '^running false'; then
    if docker exec hb-nextcloud test -f /var/www/html/version.php >/dev/null 2>&1; then
      echo '✅ Nextcloud app code hazır: /var/www/html/version.php var.'
      docker exec hb-nextcloud df -h /var/www/html/data || true
      exit 0
    fi
  fi
  if echo "$status" | grep -q 'restarting' && (( i % 10 == 0 )); then
    echo '⚠️ hb-nextcloud restart loop görünüyor. Son loglar:'
    docker logs hb-nextcloud --tail=30 || true
  fi
  sleep 3
done

echo '❌ Nextcloud hazır olmadı. Son loglar:'
docker ps -a --filter name=hb-nextcloud
docker logs hb-nextcloud --tail=160 || true
exit 1
REMOTE
chmod +x "$WORK/install.sh"
rscp "$WORK" "$VM" "/tmp/"
rssh "$VM" "sudo /tmp/hv2313-nextcloud/install.sh"
