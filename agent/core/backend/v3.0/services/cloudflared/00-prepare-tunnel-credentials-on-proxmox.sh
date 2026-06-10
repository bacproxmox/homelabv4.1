#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "cloudflared-prepare-credentials"
source "$ROOT_DIR/utils/env-loader.sh"; load_all_env
source "$ROOT_DIR/utils/env-write.sh"
require_root

DOMAIN="${DOMAIN:-bacmastercloud.com}"
TUNNEL_NAME="${CLOUDFLARE_TUNNEL_NAME:-homelab-main}"
ORIGINAL_TUNNEL_NAME="$TUNNEL_NAME"
CF_DIR="$SECRETS_DIR/cloudflared"
mkdir -p "$CF_DIR" /root/.cloudflared
chmod 700 "$CF_DIR" /root/.cloudflared

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


is_uuid(){ [[ "${1:-}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; }

install_cloudflared(){
  apt-get update -y >/dev/null
  apt-get install -y curl jq ca-certificates >/dev/null
  if ! command -v cloudflared >/dev/null 2>&1; then
    echo "📥 Proxmox üzerine geçici cloudflared binary kuruluyor..."
    curl -fsSL -o /tmp/cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    dpkg -i /tmp/cloudflared.deb >/dev/null
  fi
}

remove_cloudflared_binary(){
  echo "🧹 Proxmox üzerindeki geçici cloudflared binary kaldırılıyor; cert/JSON secrets korunacak."
  systemctl disable --now cloudflared >/dev/null 2>&1 || true
  apt-get purge -y cloudflared >/dev/null 2>&1 || rm -f /usr/local/bin/cloudflared /usr/bin/cloudflared || true
  echo "✅ Proxmox cloudflared binary kaldırıldı. $CF_DIR korundu."
}

safe_tunnel_list_json(){
  local raw
  raw="$(cloudflared tunnel list --output json 2>/dev/null || true)"
  if [[ -z "$raw" || "$raw" == "null" ]]; then echo '[]'; return; fi
  if echo "$raw" | jq -e 'type == "array"' >/dev/null 2>&1; then echo "$raw"; else echo '[]'; fi
}

get_tunnel_id_by_name(){ safe_tunnel_list_json | jq -r --arg name "$1" '.[]? | select(.name==$name) | .id' | head -n1; }

ensure_cert(){
  if [[ -f "$CF_DIR/cert.pem" && ! -f /root/.cloudflared/cert.pem ]]; then
    cp "$CF_DIR/cert.pem" /root/.cloudflared/cert.pem
    chmod 600 /root/.cloudflared/cert.pem
  fi
  if [[ ! -f /root/.cloudflared/cert.pem ]]; then
    cat <<LOGIN

🔑 Cloudflare Tunnel auth gerekiyor.
Açılan URL'yi Windows tarayıcıda açıp ${DOMAIN} domainini authorize et.
Başarılı olunca Proxmox'ta /root/.cloudflared/cert.pem oluşacak.
LOGIN
    cloudflared tunnel login
  fi
  [[ -f /root/.cloudflared/cert.pem ]] || { echo "❌ cert.pem oluşmadı."; exit 1; }
  cp /root/.cloudflared/cert.pem "$CF_DIR/cert.pem"
  chmod 600 "$CF_DIR/cert.pem" /root/.cloudflared/cert.pem
}

valid_prepared_env_for_main(){
  [[ -f "$CF_DIR/cloudflared.env" ]] || return 1
  # shellcheck disable=SC1090
  source "$CF_DIR/cloudflared.env" || true
  [[ "${CLOUDFLARE_TUNNEL_NAME:-}" == "$TUNNEL_NAME" ]] || return 1
  is_uuid "${CLOUDFLARE_TUNNEL_ID:-}" || return 1
  [[ -f "${CLOUDFLARE_CREDENTIALS_FILE:-}" ]] || return 1
}

quarantine_old_cloudflared_env_if_needed(){
  [[ -f "$CF_DIR/cloudflared.env" ]] || return 0
  # shellcheck disable=SC1090
  source "$CF_DIR/cloudflared.env" || true
  if [[ "${CLOUDFLARE_TUNNEL_NAME:-}" != "$TUNNEL_NAME" ]]; then
    local q="$CF_DIR/quarantine-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$q"
    echo "⚠️ Eski/versioned Cloudflared env görünüyor: ${CLOUDFLARE_TUNNEL_NAME:-unknown}. v3.1.1-r2 standardı: $TUNNEL_NAME"
    echo "   Eski env quarantine ediliyor; JSON dosyaları korunacak."
    mv -f "$CF_DIR/cloudflared.env" "$q/cloudflared.env" || true
  fi
}

route_dns_records(){
  echo "🌐 DNS route kayıtları Proxmox üzerinden oluşturuluyor/güncelleniyor..."
  local f name service host
  for f in "$ROOT_DIR/services/cloudflared/routes.env" "$ROOT_DIR/services/cloudflared/api-routes.env"; do
    [[ -f "$f" ]] || continue
    while IFS='|' read -r name service host; do
      [[ -z "${name:-}" || "${name:-}" =~ ^# || -z "${host:-}" || "${host:-}" =~ ^# ]] && continue
      echo "➡️ $host"
      cloudflared tunnel route dns "$TUNNEL_ID" "$host" || true
    done < "$f"
  done
}

copy_json_to_secrets(){
  local id="$1"
  local src=""
  for p in "/root/.cloudflared/${id}.json" "$CF_DIR/${id}.json"; do
    [[ -f "$p" ]] && { src="$p"; break; }
  done
  [[ -n "$src" ]] || return 1
  cp "$src" "$CF_DIR/${id}.json"
  chmod 600 "$CF_DIR/${id}.json"
}

choose_missing_json_recovery(){
  local existing_id="$1" ans default_name
  default_name="${ORIGINAL_TUNNEL_NAME}-$(date +%Y%m%d-%H%M)"
  cat <<RECOVERY

⚠️ Cloudflare'da '${ORIGINAL_TUNNEL_NAME}' tunnel var ama local credential JSON yok.
   Tunnel credential JSON Cloudflare panelinden sonradan indirilemez.

Seçenekler:
  1) Yeni tunnel adıyla devam et: ${default_name}
  2) Eski tunnel'ı Cloudflare panelinden sildim; aynı adı tekrar dene
  3) Cloudflared'i şimdilik skip et

Not: Cloudflare API token sorulmaz/kullanılmaz; bu akış cloudflared login + cert.pem + JSON credential kullanır.
RECOVERY

  if [[ -n "${CLOUDFLARED_MISSING_JSON_ACTION:-}" ]]; then
    ans="$CLOUDFLARED_MISSING_JSON_ACTION"
  elif [[ -t 0 ]]; then
    read -r -p "Seçim [1/2/3, varsayılan 1]: " ans
    ans="${ans:-1}"
  else
    ans="1"
  fi

  case "$ans" in
    1|new|NEW)
      TUNNEL_NAME="${CLOUDFLARED_NEW_TUNNEL_NAME:-$default_name}"
      echo "➡️ Yeni tunnel adı seçildi: $TUNNEL_NAME"
      return 0
      ;;
    2|retry|same|SAME)
      if is_uuid "$(get_tunnel_id_by_name "$ORIGINAL_TUNNEL_NAME" || true)"; then
        echo "❌ '${ORIGINAL_TUNNEL_NAME}' hâlâ Cloudflare'da mevcut. Önce panelden sil veya seçim 1 ile yeni ad kullan."
        return 1
      fi
      TUNNEL_NAME="$ORIGINAL_TUNNEL_NAME"
      echo "➡️ Aynı adla yeniden oluşturma denenecek: $TUNNEL_NAME"
      return 0
      ;;
    3|skip|SKIP)
      echo "⚠️ Cloudflared prepare kullanıcı tercihiyle skip edildi. Bu adım resume sonrası tekrar denenebilir."
      exit 75
      ;;
    *)
      echo "❌ Geçersiz seçim: $ans"
      return 1
      ;;
  esac
}

create_or_reuse_main_tunnel(){
  local id out
  id="$(get_tunnel_id_by_name "$TUNNEL_NAME" || true)"

  if is_uuid "$id"; then
    echo "✅ Cloudflare tunnel bulundu: $TUNNEL_NAME / $id"
    if copy_json_to_secrets "$id"; then
      TUNNEL_ID="$id"
      return 0
    fi
    choose_missing_json_recovery "$id" || exit 1
    id="$(get_tunnel_id_by_name "$TUNNEL_NAME" || true)"
    if is_uuid "$id"; then
      echo "✅ Cloudflare tunnel bulundu: $TUNNEL_NAME / $id"
      if copy_json_to_secrets "$id"; then
        TUNNEL_ID="$id"
        return 0
      fi
      echo "❌ '$TUNNEL_NAME' için local credential JSON hâlâ yok."
      exit 1
    fi
  fi

  echo "🕳️ Tunnel oluşturuluyor: $TUNNEL_NAME"
  out="$(cloudflared tunnel create "$TUNNEL_NAME" 2>&1 || true)"
  echo "$out"
  id="$(echo "$out" | grep -Eo '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' | head -n1 || true)"
  if ! is_uuid "$id"; then id="$(get_tunnel_id_by_name "$TUNNEL_NAME" || true)"; fi
  if ! is_uuid "$id"; then
    local json
    json="$(find /root/.cloudflared -maxdepth 1 -type f -name '*.json' -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR==1{print $2}')"
    [[ -n "$json" ]] && id="$(basename "$json" .json)"
  fi
  is_uuid "$id" || { echo "❌ Tunnel ID bulunamadı."; exit 1; }
  copy_json_to_secrets "$id" || { echo "❌ Credential JSON yok: /root/.cloudflared/${id}.json"; exit 1; }
  TUNNEL_ID="$id"
}

install_cloudflared
quarantine_old_cloudflared_env_if_needed

if valid_prepared_env_for_main; then
  echo "✅ Cloudflare Tunnel credentials zaten hazır: ${CLOUDFLARE_TUNNEL_NAME} / ${CLOUDFLARE_TUNNEL_ID}"
  echo "   Tekrar login/tunnel create denenmeyecek; DNS route idempotent olarak doğrulanacak."
  TUNNEL_ID="$CLOUDFLARE_TUNNEL_ID"
else
  ensure_cert
  create_or_reuse_main_tunnel
fi

ensure_route_files
route_dns_records

{
  write_env_header
  write_env_line CLOUDFLARE_TUNNEL_NAME "$TUNNEL_NAME"
  write_env_line CLOUDFLARE_TUNNEL_ID "$TUNNEL_ID"
  write_env_line CLOUDFLARE_CERT_FILE "$CF_DIR/cert.pem"
  write_env_line CLOUDFLARE_CREDENTIALS_FILE "$CF_DIR/${TUNNEL_ID}.json"
} > "$CF_DIR/cloudflared.env"
chmod 600 "$CF_DIR/cloudflared.env"

cat <<DONE
✅ Cloudflare Tunnel credentials hazırlandı.
  Tunnel : $TUNNEL_NAME
  ID     : $TUNNEL_ID
  Secret : $CF_DIR/${TUNNEL_ID}.json

Not: cert.pem Proxmox secrets altında kalır; VM103'e sadece tunnel JSON kopyalanacak.
DONE

remove_cloudflared_binary
