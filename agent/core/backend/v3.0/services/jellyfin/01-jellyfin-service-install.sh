#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "jellyfin-service-install"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"
source "$ROOT_DIR/utils/env-write.sh"
VM=106
WORK=/tmp/hv2313-jellyfin
rm -rf "$WORK"; mkdir -p "$WORK"
{
  write_env_header
  write_env_line TZ "${TZ:-Europe/Istanbul}"
  write_env_line PUID "${MEDIA_UID:-1000}"
  write_env_line PGID "${MEDIA_GID:-1000}"
} > "$WORK/.env"
cat > "$WORK/install.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /tmp/hv2313-jellyfin
mkdir -p /opt/homelab/jellyfin/config/jellyfin /mnt/media/movies /mnt/media/series
cp .env /opt/homelab/jellyfin/.env
cd /opt/homelab/jellyfin
GPU_BLOCK=""
if [[ -d /dev/dri && -e /dev/dri/renderD128 ]]; then
  echo "✅ /dev/dri bulundu. Jellyfin VAAPI/iGPU mode compose yazılıyor."
  GPU_BLOCK='    group_add:
      - "44"
      - "109"
    devices:
      - /dev/dri:/dev/dri'
else
  echo "⚠️ /dev/dri bulunamadı. Jellyfin CPU mode ile kurulacak."
  echo "   GPU repair: bash maintenance/repair/repair-gpu-passthrough.sh"
fi
cat > docker-compose.yml <<EOFYAML
networks:
  homelab:
    external: true
services:
  jellyfin:
    image: lscr.io/linuxserver/jellyfin:latest
    container_name: hb-jellyfin
    restart: unless-stopped
    networks: [homelab]
${GPU_BLOCK}
    environment:
      - PUID=\${PUID}
      - PGID=\${PGID}
      - TZ=\${TZ}
    volumes:
      - ./config/jellyfin:/config
      - /mnt/media/movies:/data/movies
      - /mnt/media/series:/data/series
    ports:
      - "8096:8096"
EOFYAML
# remove empty line indentation if no GPU block
python3 - <<'PY'
from pathlib import Path
p=Path('docker-compose.yml')
s=p.read_text()
s=s.replace('\n\n    environment:', '\n    environment:')
p.write_text(s)
PY
docker network create homelab >/dev/null 2>&1 || true
docker compose pull
docker compose up -d
if docker ps --format '{{.Names}} {{.Status}}' | grep -q '^hb-jellyfin '; then
  echo "✅ Jellyfin container started."
else
  echo "❌ Jellyfin container başlamadı. Loglar:"
  docker logs hb-jellyfin --tail=120 || true
  exit 1
fi
REMOTE
chmod +x "$WORK/install.sh"
rscp "$WORK" "$VM" "/tmp/"
rssh "$VM" "sudo /tmp/hv2313-jellyfin/install.sh"
