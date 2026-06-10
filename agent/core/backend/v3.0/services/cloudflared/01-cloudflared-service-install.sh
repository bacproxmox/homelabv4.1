#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "cloudflared-service-install"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/remote.sh"

VM=103
DOMAIN="${DOMAIN:-bacmastercloud.com}"
TUNNEL_NAME="${CLOUDFLARE_TUNNEL_NAME:-homelab-main}"
CF_DIR="$SECRETS_DIR/cloudflared"
WORK="/tmp/hv247-cloudflared"
rm -rf "$WORK"; mkdir -p "$WORK"


ensure_route_files(){
  local top_dir="$ROOT_DIR/services/cloudflared"
  local backend_dir="$ROOT_DIR/services/cloudflared"
  mkdir -p "$top_dir" 2>/dev/null || true
  if [[ ! -f "$top_dir/routes.env" ]]; then
    if [[ -f "$top_dir/routes.defaults" ]]; then
      cp "$top_dir/routes.defaults" "$top_dir/routes.env"
    else
      cat > "$top_dir/routes.env" <<'ROUTES'
# Homelab canonical Cloudflared routes
# Format: NAME|URL|HOSTNAME
Proxmox|https://192.168.50.100:8006|pve.bacmastercloud.com
TrueNAS|http://192.168.50.101|truenas.bacmastercloud.com
qBittorrent|http://192.168.50.102:8080|qbittorrent.bacmastercloud.com
Sonarr|http://192.168.50.102:8989|sonarr.bacmastercloud.com
Radarr|http://192.168.50.102:7878|radarr.bacmastercloud.com
Prowlarr|http://192.168.50.102:9696|prowlarr.bacmastercloud.com
Bazarr|http://192.168.50.102:6767|bazarr.bacmastercloud.com
Seerr|http://192.168.50.102:5055|bacneyplus.bacmastercloud.com
UptimeKuma|http://192.168.50.103:3001|status.bacmastercloud.com
Nextcloud|http://192.168.50.104:8080|cloud.bacmastercloud.com
HomeAssistant|http://192.168.50.105:8123|home.bacmastercloud.com
Jellyfin|http://192.168.50.106:8096|bacsflix.bacmastercloud.com
Immich|http://192.168.50.106:2283|photos.bacmastercloud.com
OpenWebUI|http://192.168.50.106:3000|ai.bacmastercloud.com
Lidarr|http://192.168.50.106:8686|music.bacmastercloud.com
Chia|http://192.168.50.107:8555|chia.bacmastercloud.com
PBS|https://192.168.50.110:8007|pbs.bacmastercloud.com
ROUTES
    fi
  fi
  if [[ ! -f "$top_dir/api-routes.env" ]]; then
    if [[ -f "$top_dir/api-routes.defaults" ]]; then
      cp "$top_dir/api-routes.defaults" "$top_dir/api-routes.env"
    else
      cat > "$top_dir/api-routes.env" <<'APIROUTES'
# Homelab API/mobile Cloudflared routes
# Format: NAME|URL|HOSTNAME
ProxmoxAPI|https://192.168.50.100:8006|pve-api.bacmastercloud.com
TrueNASAPI|http://192.168.50.101|truenas-api.bacmastercloud.com
qBittorrentAPI|http://192.168.50.102:8080|qbittorrent-api.bacmastercloud.com
SonarrAPI|http://192.168.50.102:8989|sonarr-api.bacmastercloud.com
RadarrAPI|http://192.168.50.102:7878|radarr-api.bacmastercloud.com
ProwlarrAPI|http://192.168.50.102:9696|prowlarr-api.bacmastercloud.com
BazarrAPI|http://192.168.50.102:6767|bazarr-api.bacmastercloud.com
SeerrAPI|http://192.168.50.102:5055|bacneyplus-api.bacmastercloud.com
UptimeKumaAPI|http://192.168.50.103:3001|status-api.bacmastercloud.com
NextcloudAPI|http://192.168.50.104:8080|cloud-api.bacmastercloud.com
HomeAssistantAPI|http://192.168.50.105:8123|home-api.bacmastercloud.com
JellyfinAPI|http://192.168.50.106:8096|bacsflix-api.bacmastercloud.com
ImmichAPI|http://192.168.50.106:2283|photos-api.bacmastercloud.com
OpenWebUIAPI|http://192.168.50.106:3000|ai-api.bacmastercloud.com
LidarrAPI|http://192.168.50.106:8686|music-api.bacmastercloud.com
ChiaAPI|http://192.168.50.107:8555|chia-api.bacmastercloud.com
PBSAPI|https://192.168.50.110:8007|pbs-api.bacmastercloud.com
APIROUTES
    fi
  fi
  chmod 644 "$top_dir/routes.env" "$top_dir/api-routes.env" 2>/dev/null || true
}

ensure_route_files
cp "$ROOT_DIR/services/cloudflared/routes.env" "$WORK/routes.env"
cp "$ROOT_DIR/services/cloudflared/api-routes.env" "$WORK/api-routes.env"

if [[ ! -f "$CF_DIR/cloudflared.env" ]]; then
  cat <<MSG
❌ Cloudflared early credentials yok: $CF_DIR/cloudflared.env
Önce Install Menu -> 15) Prepare Cloudflare Tunnel credentials early çalıştır.
v3.1.1-r2 standardı: Proxmox'ta browser auth + DNS route, VM103'te JSON-only final service.
MSG
  exit 1
fi

# shellcheck disable=SC1090
source "$CF_DIR/cloudflared.env"
if [[ "${CLOUDFLARE_TUNNEL_NAME:-}" != "$TUNNEL_NAME" ]]; then
  echo "❌ Cloudflared tunnel adı uyumsuz. Beklenen: $TUNNEL_NAME, mevcut: ${CLOUDFLARE_TUNNEL_NAME:-unknown}"
  echo "   Install Menu -> 15 ile homelab-main credentials yeniden hazırla."
  exit 1
fi
if [[ -z "${CLOUDFLARE_TUNNEL_ID:-}" || ! -f "${CLOUDFLARE_CREDENTIALS_FILE:-}" ]]; then
  echo "❌ Cloudflared credential eksik/geçersiz. Env: $CF_DIR/cloudflared.env"
  exit 1
fi

cp "$CF_DIR/cloudflared.env" "$WORK/prepared-cloudflared.env"
cp "$CLOUDFLARE_CREDENTIALS_FILE" "$WORK/prepared-credentials.json"
chmod 600 "$WORK/prepared-credentials.json"

cat > "$WORK/install-cloudflared-native.sh" <<'REMOTE'
#!/usr/bin/env bash
set -Eeuo pipefail
set +H

DOMAIN="${DOMAIN:-bacmastercloud.com}"
EXPECTED_TUNNEL_NAME="${TUNNEL_NAME:-homelab-main}"
ROUTES_FILE="/tmp/hv247-cloudflared/routes.env"
API_ROUTES_FILE="/tmp/hv247-cloudflared/api-routes.env"
ENV_FILE="/tmp/hv247-cloudflared/prepared-cloudflared.env"
CRED_SRC="/tmp/hv247-cloudflared/prepared-credentials.json"

export DEBIAN_FRONTEND=noninteractive
say(){ echo -e "$*"; }
die(){ say "❌ $*"; exit 1; }
is_uuid(){ [[ "${1:-}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; }

install_packages(){
  say "📦 cloudflared paketleri kontrol ediliyor..."
  apt-get update >/dev/null
  apt-get install -y curl jq python3 ca-certificates >/dev/null
  if ! command -v cloudflared >/dev/null 2>&1; then
    say "📥 cloudflared kuruluyor..."
    curl -fsSL -o /tmp/cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    dpkg -i /tmp/cloudflared.deb >/dev/null
  fi
}

load_prepared_credentials(){
  [[ -f "$ENV_FILE" ]] || die "Prepared cloudflared env yok: $ENV_FILE"
  [[ -f "$CRED_SRC" ]] || die "Prepared tunnel JSON yok: $CRED_SRC"
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  TUNNEL_NAME="${CLOUDFLARE_TUNNEL_NAME:-}"
  TUNNEL_ID="${CLOUDFLARE_TUNNEL_ID:-}"
  [[ "$TUNNEL_NAME" == "$EXPECTED_TUNNEL_NAME" ]] || die "Tunnel adı uyumsuz: $TUNNEL_NAME != $EXPECTED_TUNNEL_NAME"
  is_uuid "$TUNNEL_ID" || die "Tunnel ID geçersiz: ${TUNNEL_ID:-empty}"
  mkdir -p /etc/cloudflared
  chmod 700 /etc/cloudflared || true
  cp "$CRED_SRC" "/etc/cloudflared/${TUNNEL_ID}.json"
  chmod 600 "/etc/cloudflared/${TUNNEL_ID}.json"
  say "✅ VM103 JSON-only credential kullanılıyor: $TUNNEL_NAME / $TUNNEL_ID"
}

write_config(){
  local CONFIG="/etc/cloudflared/config.yml"
  [[ -f "$CONFIG" ]] && cp "$CONFIG" "${CONFIG}.bak.$(date +%Y%m%d-%H%M%S)" || true

  write_ingress_entry(){
    local name="$1" service="$2" host="$3"
    [[ -z "$host" || "$host" =~ ^# ]] && return 0
    cat >> "$CONFIG" <<YAML
  - hostname: ${host}
    service: ${service}
YAML
    if [[ "$service" == https://192.168.50.100:8006* || "$service" == https://192.168.50.110:8007* ]]; then
      cat >> "$CONFIG" <<'YAML'
    originRequest:
      noTLSVerify: true
YAML
    fi
  }

  say "📝 config.yml yazılıyor: $CONFIG"
  cat > "$CONFIG" <<YAML
# Generated by Homelab v3.1.1-r2
# VM103 uses tunnel-specific JSON only. cert.pem/browser auth/DNS route stay on Proxmox.
tunnel: ${TUNNEL_ID}
credentials-file: /etc/cloudflared/${TUNNEL_ID}.json

protocol: quic
loglevel: info

ingress:
YAML

  while IFS='|' read -r name service host; do
    [[ -z "${name:-}" || "${name:-}" =~ ^# ]] && continue
    write_ingress_entry "$name" "$service" "$host"
  done < "$ROUTES_FILE"

  while IFS='|' read -r name service host; do
    [[ -z "${name:-}" || "${name:-}" =~ ^# ]] && continue
    write_ingress_entry "$name" "$service" "$host"
  done < "$API_ROUTES_FILE"

  cat >> "$CONFIG" <<'YAML'
  - service: http_status:404
YAML

  chmod 600 "$CONFIG" "/etc/cloudflared/${TUNNEL_ID}.json"
  say "🔎 Ingress validate..."
  cloudflared tunnel --config "$CONFIG" ingress validate
}

install_systemd_unit(){
  say "🔧 cloudflared systemd unit yazılıyor..."
  cat > /etc/systemd/system/cloudflared.service <<'UNIT'
[Unit]
Description=Cloudflare Tunnel - Homelab
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/cloudflared --no-autoupdate --config /etc/cloudflared/config.yml tunnel run
Restart=always
RestartSec=5
TimeoutStartSec=0
User=root

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable cloudflared >/dev/null
  systemctl restart cloudflared
  sleep 5
  systemctl --no-pager --full status cloudflared | sed -n '1,28p' || true
  systemctl is-active --quiet cloudflared || die "cloudflared service active değil. journalctl -u cloudflared kontrol et."
}

final_validate(){
  say "🧪 Final doğrulama..."
  test -f "/etc/cloudflared/${TUNNEL_ID}.json" || die "Credentials yok"
  test -f /etc/cloudflared/config.yml || die "Config yok"
  cloudflared tunnel --config /etc/cloudflared/config.yml ingress validate >/dev/null
  say "✅ cloudflared local validation OK. DNS route komutları v3.1.1-r2'de Proxmox early phase içinde çalışır."
}

say
say "🌩️ Homelab v3.1.1-r2 - Cloudflared JSON-only final service"
say "Tunnel : $EXPECTED_TUNNEL_NAME"
say "Domain : $DOMAIN"
say
install_packages
load_prepared_credentials
write_config
install_systemd_unit
final_validate
say
say "✅ Cloudflared tamamlandı."
say "Config: /etc/cloudflared/config.yml"
say "Tunnel: $TUNNEL_NAME / $TUNNEL_ID"
REMOTE

chmod +x "$WORK/install-cloudflared-native.sh"
rscp "$WORK" "$VM" "/tmp/"
rssh "$VM" "sudo DOMAIN='$DOMAIN' TUNNEL_NAME='$TUNNEL_NAME' bash /tmp/hv247-cloudflared/install-cloudflared-native.sh"
