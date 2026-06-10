#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/utils/env-loader.sh"
source "$ROOT_DIR/utils/logging.sh"
start_log "install-menu"

run(){
  echo
  echo "▶️ $*"
  if bash "$ROOT_DIR/$1"; then
    return 0
  else
    local c=$?
    echo "❌ Script hata verdi ($c): $1"
    return "$c"
  fi
}

quarantine_truenas_api_envs(){
  local reason="${1:-fresh TrueNAS API regeneration required}"
  local secrets="${SECRETS_DIR:-/root/homelab-secrets}"
  local stamp qdir f
  stamp="$(date +%Y%m%d-%H%M%S)"
  qdir="$secrets/quarantine/truenas-api-${stamp}"
  mkdir -p "$qdir"
  chmod 700 "$secrets" "$secrets/quarantine" "$qdir" 2>/dev/null || true

  shopt -s nullglob
  for f in \
    "$secrets/truenas-api.env" \
    "$secrets/truenas.env" \
    "$secrets"/*truenas-api* \
    "$secrets"/*TRUENAS_API*; do
    [[ -e "$f" ]] || continue
    # Do not recursively quarantine the quarantine folder itself.
    [[ "$f" == "$secrets/quarantine"* ]] && continue
    echo "⚠️ Eski/import edilmiş TrueNAS API dosyası kullanılmayacak: $(basename "$f")"
    mv -f "$f" "$qdir/" 2>/dev/null || rm -f "$f" || true
  done
  shopt -u nullglob

  if [[ -z "$(find "$qdir" -type f -print -quit 2>/dev/null)" ]]; then
    rmdir "$qdir" 2>/dev/null || true
  else
    echo "ℹ️ TrueNAS API dosyaları quarantine edildi: $qdir"
    echo "   Sebep: $reason"
  fi
}

mark_fresh_truenas_api_required(){
  local marker="${SECRETS_DIR:-/root/homelab-secrets}/.fresh-truenas-api-required"
  mkdir -p "${SECRETS_DIR:-/root/homelab-secrets}"
  touch "$marker"
  chmod 600 "$marker" 2>/dev/null || true
}

clear_fresh_truenas_api_marker(){
  rm -f "${SECRETS_DIR:-/root/homelab-secrets}/.fresh-truenas-api-required" 2>/dev/null || true
}

ensure_truenas_api_ready(){
  local api_env="${SECRETS_DIR:-/root/homelab-secrets}/truenas-api.env"
  local login_env="${SECRETS_DIR:-/root/homelab-secrets}/truenas-login.env"
  local marker="${SECRETS_DIR:-/root/homelab-secrets}/.fresh-truenas-api-required"
  local force_new="${HOMELAB_FORCE_NEW_TRUENAS_API:-0}"

  # Fresh TrueNAS installs must always generate a fresh API key. A key imported
  # from an encrypted secrets backup can point at an old TrueNAS install/state and
  # cause misleading HTTP 500/middleware errors. In guided fresh installs or after
  # the manual TrueNAS checkpoint, ignore any existing truenas-api.env and create
  # a new one via SSH.
  if [[ "$force_new" == "1" || -f "$marker" ]]; then
    echo "🔑 Fresh TrueNAS API key zorunlu; mevcut/import edilmiş API env kullanılmayacak."
    quarantine_truenas_api_envs "fresh TrueNAS API regeneration"
  elif [[ -f "$api_env" ]]; then
    echo "✅ TrueNAS API env mevcut: $api_env"
    return 0
  fi

  cat <<CHECK

TrueNAS API env hazır değil veya fresh install için yeniden üretilecek:
  $api_env

v2.4.7 akışı:
  1) TrueNAS manuel kurulumu bitmiş olmalı
  2) Router DHCP reservation önerisi: 02:23:14:00:01:01 -> 192.168.50.101
  3) TrueNAS WebUI > System Settings > Services > SSH açılmalı
     - Allow Password Authentication: ON
     - Password Login Groups: builtin_administrators veya truenas_admin admin grubu
     - Save, SSH Start
  4) Post-install helper tank/private import eder ve YENİ truenas-api.env oluşturur

Not: truenas_admin şifresi Option 1'de $login_env içine kaydedilmiş olmalı.
CHECK

  if [[ ! -f "$login_env" ]]; then
    echo "❌ $login_env yok. Önce Install Menu -> 1) Bootstrap secrets/env çalıştır."
    return 1
  fi

  echo "✅ truenas-login.env mevcut. Post-install helper otomatik çalışacak ve yeni API key üretecek."
  echo; echo "▶️ services/truenas/00-truenas-postinstall-import-api-network.sh"
  if ! TRUENAS_SSH_READY_ASSUMED=1 TRUENAS_SKIP_BOOT_FIX=1 bash "$ROOT_DIR/services/truenas/00-truenas-postinstall-import-api-network.sh"; then
    echo "❌ TrueNAS post-install helper başarısız oldu."
    return 1
  fi
  [[ -f "$api_env" ]] || { echo "❌ Helper bitti ama $api_env oluşmadı."; return 1; }
  clear_fresh_truenas_api_marker
  echo "✅ Fresh TrueNAS API env üretildi: $api_env"
  return 0
}

truenas_vm_mac(){
  qm config 101 2>/dev/null | sed -nE 's/^net[0-9]+:.*=(([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}).*/\1/p' | head -n1 | tr '[:upper:]' '[:lower:]'
}

truenas_vm_bridge(){
  qm config 101 2>/dev/null | sed -nE 's/^net[0-9]+:.*bridge=([^, ]+).*/\1/p' | head -n1
}

switch_truenas_to_disk_boot(){
  echo
  echo "💿 TrueNAS VM101 installer ISO/CD kaldırılıyor ve disk boot'a alınıyor..."
  qm stop 101 || true
  sleep 3
  qm set 101 --ide2 none || true
  qm set 101 --boot order=scsi0
  qm start 101
  echo "✅ VM101 diskten boot edecek şekilde başlatıldı."
  echo "⏳ TrueNAS boot için 60 saniye bekleniyor..."
  sleep 60
}

start_truenas_installer_if_needed(){
  if ! qm status 101 >/dev/null 2>&1; then
    echo "❌ VM101 bulunamadı. Önce vm/101-truenas-vm-install.sh çalışmalı."
    return 1
  fi
  if qm status 101 2>/dev/null | grep -q 'status: running'; then
    echo "✅ VM101 zaten çalışıyor."
  else
    echo "▶️ VM101 TrueNAS installer başlatılıyor..."
    qm start 101 || true
    sleep 5
  fi
  echo "ℹ️ Proxmox UI > VM101 > Console ekranından TrueNAS installer'ı tamamla."
}

find_truenas_ip_by_mac(){
  local mac bridge subnet ip
  mac="$(truenas_vm_mac)"
  bridge="$(truenas_vm_bridge)"
  bridge="${bridge:-vmbr0}"
  subnet="192.168.50.0/24"
  [[ -n "$mac" ]] || return 1
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y nmap arp-scan >/dev/null 2>&1 || true
  ip neigh flush all >/dev/null 2>&1 || true
  nmap -sn "$subnet" >/dev/null 2>&1 || true
  ip="$(ip neigh show | awk -v mac="$mac" '$1 ~ /^192\.168\.50\./ && tolower($5)==mac {print $1; exit}')"
  if [[ -z "$ip" ]]; then
    ip="$(arp-scan -I "$bridge" "$subnet" 2>/dev/null | awk -v mac="$mac" '$1 ~ /^192\.168\.50\./ && tolower($2)==mac {print $1; exit}')"
  fi
  [[ -n "$ip" ]] && echo "$ip"
}

refresh_truenas_known_host(){
  local ip="${1:-192.168.50.101}"
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  touch /root/.ssh/known_hosts
  chmod 600 /root/.ssh/known_hosts

  # Fresh TrueNAS installs reuse 192.168.50.101 with a new SSH host key.
  # Remove stale keys before testing SSH so the pipeline does not stop at
  # "REMOTE HOST IDENTIFICATION HAS CHANGED".
  ssh-keygen -f /root/.ssh/known_hosts -R "$ip" >/dev/null 2>&1 || true
  ssh-keygen -f /root/.ssh/known_hosts -R "[$ip]:22" >/dev/null 2>&1 || true
  ssh-keyscan -H "$ip" >> /root/.ssh/known_hosts 2>/dev/null || true
}

test_truenas_ssh_from_login_env(){
  local ip="$1" login_env user pass
  login_env="${SECRETS_DIR:-/root/homelab-secrets}/truenas-login.env"
  [[ -f "$login_env" ]] || return 1
  # shellcheck disable=SC1090
  source "$login_env"
  user="${TRUENAS_SSH_USER:-truenas_admin}"
  pass="${TRUENAS_SSH_PASS:-}"
  [[ -n "$pass" ]] || return 1
  apt-get install -y sshpass openssh-client >/dev/null 2>&1 || true
  refresh_truenas_known_host "$ip"
  sshpass -p "$pass" ssh     -o StrictHostKeyChecking=accept-new     -o UserKnownHostsFile=/root/.ssh/known_hosts     -o ConnectTimeout=8     -o PreferredAuthentications=password     -o PubkeyAuthentication=no     "$user@$ip" 'echo SSH_OK' 2>/tmp/truenas-ssh-test.err | grep -q SSH_OK
}

truenas_checkpoint_already_done(){
  local ip="${1:-192.168.50.101}"
  if qm config 101 2>/dev/null | grep -Eq '^ide2: .*iso'; then
    return 1
  fi
  if (curl -fsS --max-time 5 "http://$ip" >/dev/null 2>&1 || ping -c1 -W1 "$ip" >/dev/null 2>&1) && test_truenas_ssh_from_login_env "$ip"; then
    echo "✅ TrueNAS disk boot + WebUI/SSH checkpoint zaten tamam görünüyor: $ip"
    return 0
  fi
  return 1
}

wait_for_truenas_manual_install_and_ssh(){
  local ans ip web_ans ssh_ans login_env user pass found
  login_env="${SECRETS_DIR:-/root/homelab-secrets}/truenas-login.env"
  ip="192.168.50.101"

  if truenas_checkpoint_already_done "$ip"; then
    return 0
  fi

  echo
  echo "=================================================="
  echo " MANUEL DURAK: TrueNAS kurulumu"
  echo "=================================================="
  echo "1) VM101 Console'da TrueNAS installer'ı manuel bitir."
  echo "2) Kurulumda SADECE 64GB OS diskini seç."
  echo "3) Kurulum bittiğinde burada 'y' yaz; script ISO'yu kaldırıp VM101'i disk boot'a alacak."
  echo "4) Sonra WebUI ve SSH kontrolleri yapılacak."

  start_truenas_installer_if_needed || return 1

  while true; do
    read -r -p "TrueNAS kurulumu bitti mi? [y/N/q]: " ans
    case "$ans" in
      [Yy]*) break ;;
      [Qq]*) echo "Pipeline kullanıcı tarafından durduruldu."; return 1 ;;
      *) echo "⏳ TrueNAS kurulumu için bekleniyor..."; sleep 10 ;;
    esac
  done

  if qm config 101 2>/dev/null | grep -Eq '^ide2: .*iso'; then
    switch_truenas_to_disk_boot
  else
    echo "ℹ️ VM101 üzerinde installer ISO görünmüyor; boot-fix adımı atlandı."
    qm start 101 >/dev/null 2>&1 || true
  fi

  while true; do
    echo
    echo "🌐 TrueNAS WebUI kontrolü"
    echo "Önce router reservation/fixed MAC IP deneniyor:"
    echo "  http://$ip"
    if curl -fsS --max-time 5 "http://$ip" >/dev/null 2>&1 || ping -c1 -W1 "$ip" >/dev/null 2>&1; then
      echo "✅ $ip erişilebilir görünüyor."
    else
      echo "⚠️ $ip henüz erişilebilir görünmüyor."
    fi
    read -r -p "TrueNAS WebUI http://$ip üzerinden erişilebilir mi? [y/N/ara/q]: " web_ans
    case "$web_ans" in
      [Yy]*) break ;;
      [Qq]*) return 1 ;;
      ara|ARA|[Nn]*)
        echo "🔎 DHCP/MAC ağ taraması başlıyor..."
        found="$(find_truenas_ip_by_mac || true)"
        if [[ -n "$found" ]]; then
          ip="$found"
          echo "✅ TrueNAS aday IP bulundu: http://$ip"
        else
          echo "❌ TrueNAS IP bulunamadı. 10 saniye sonra tekrar sorulacak."
          sleep 10
        fi
        ;;
      *) echo "Lütfen y, n/ara veya q yaz." ;;
    esac
  done

  cat <<SSHNOTE

==================================================
 SSH açma adımı
==================================================
TrueNAS WebUI > System Settings > Services > SSH > Edit:
  - Allow Password Authentication: ON
  - Password Login Groups: builtin_administrators veya truenas_admin'in admin grubu
  - Save
  - SSH Start
  - İstersen Start Automatically açık kalsın

SSHNOTE

  [[ -f "$login_env" ]] || { echo "❌ $login_env yok. Önce Install Menu -> 1 çalışmalı."; return 1; }
  # shellcheck disable=SC1090
  source "$login_env"
  user="${TRUENAS_SSH_USER:-truenas_admin}"
  pass="${TRUENAS_SSH_PASS:-}"
  [[ -n "$pass" ]] || { echo "❌ TRUENAS_SSH_PASS boş."; return 1; }
  apt-get install -y sshpass >/dev/null 2>&1 || true

  while true; do
    read -r -p "SSH açıldı mı? [y/N/q]: " ssh_ans
    case "$ssh_ans" in
      [Yy]*)
        if test_truenas_ssh_from_login_env "$ip"; then
          echo "✅ TrueNAS SSH bağlantısı başarılı: $user@$ip"
          if grep -q '^TRUENAS_HOST=' "$login_env"; then
            sed -i "s/^TRUENAS_HOST=.*/TRUENAS_HOST=$ip/" "$login_env" || true
          else
            echo "TRUENAS_HOST=$ip" >> "$login_env"
          fi
          mark_fresh_truenas_api_required
          return 0
        fi
        echo "❌ SSH bağlanılamadı."
        cat /tmp/truenas-ssh-test.err 2>/dev/null || true
        echo "Hatırlatma: SSH Running olmalı, Allow Password Authentication açık olmalı, Password Login Groups içine builtin_administrators veya truenas_admin'in admin grubu eklenmeli."
        ;;
      [Qq]*) return 1 ;;
      *) echo "⏳ SSH açılması bekleniyor..."; sleep 8 ;;
    esac
  done
}

run_truenas_vm_and_checkpoint(){
  run_required vm/101-truenas-vm-install.sh || return $?
  wait_for_truenas_manual_install_and_ssh || return $?
}

run_required(){
  local script="$1"
  local c=0
  run "$script" || c=$?
  if [[ "$c" -eq 0 ]]; then
    return 0
  fi
  echo
  echo "❌ Kritik adım başarısız oldu: $script ($c)"
  echo "Pipeline güvenli şekilde durduruldu. Loglar: ${LOG_DIR:-/root/homelab-logs}"
  return "$c"
}

run_best_effort(){
  local script="$1"
  local c=0
  run "$script" || c=$?
  if [[ "$c" -eq 0 ]]; then
    return 0
  fi
  echo "⚠️ Opsiyonel/devam edilebilir adım hata verdi, pipeline devam edecek: $script ($c)"
  return 0
}

run_core_services(){
  run_required services/arr/01-arr-service-install.sh || return $?
  run_required services/seerr/01-seerr-service-install.sh || return $?
  run_required services/uptime-kuma/01-uptime-kuma-service-install.sh || return $?
  run_required services/nextcloud/01-nextcloud-service-install.sh || return $?
  run_required services/jellyfin/01-jellyfin-service-install.sh || return $?
  run_required services/immich/01-immich-service-install.sh || return $?
  run_required services/ollama/01-ollama-openwebui-service-install.sh || return $?
  run_required services/lidarr/01-lidarr-service-install.sh || return $?
  run_required services/homeassistant/01-homeassistant-service-install.sh || return $?
  run_required services/pbs/01-pbs-service-install.sh || return $?
}


run_early_cloudflared_prepare(){
  cat <<'CFPREP'

==================================================
 EARLY CLOUDFLARED CREDENTIAL PREPARE
==================================================
Bu adım Proxmox üzerinde geçici cloudflared çalıştırıp browser auth linkini erken gösterir.
Başarılı olursa cert.pem + tunnel JSON /root/homelab-secrets/cloudflared altında saklanır.
VM103 kurulunca final Cloudflared aşaması bu hazır JSON'u kullanır ve tekrar auth istemez.
CFPREP
  echo
  read -r -p "Cloudflare Tunnel credentials şimdi hazırlansın mı? [y/N]: " cfprep_ans
  if [[ ! "$cfprep_ans" =~ ^[Yy]$ ]]; then
    echo "ℹ️ Erken Cloudflared credential hazırlığı atlandı. Final aşamada auth yapılabilir."
    return 0
  fi
  run_best_effort services/cloudflared/00-prepare-tunnel-credentials-on-proxmox.sh
}

run_final_cloudflared(){
  cat <<'CLOUDFLARE_NOTE'

==================================================
 FINAL REMOTE ACCESS: Cloudflared
==================================================
Bu adım VM103 üzerinde cloudflared servisini kurar.
v2.4.7 standardında browser auth ve DNS route işlemleri Proxmox erken credential aşamasında yapılır.
Final aşama sadece homelab-main JSON credential kullanır.
CLOUDFLARE_NOTE
  echo
  echo "Cloudflared final setup guided akışta otomatik çalışacak; VM103 auth/DNS route çalıştırmayacak."
  run_required services/cloudflared/01-cloudflared-service-install.sh || return $?
}

run_repair_basics(){
  run_best_effort config/nextcloud/01-nextcloud-local-and-cloudflare-fix.sh
  run_best_effort config/nextcloud/04-bacscloud-production-hardening.sh
  run_best_effort config/nextcloud/06-bacscloud-admin-overview-cleanup.sh
  run_best_effort config/nextcloud/07-bacscloud-social-login-and-registration.sh
  run_best_effort config/immich/01-immich-storage-verify.sh
  run_best_effort services/cloudflared/02-generate-ingress-config-reference.sh
}

run_phase4(){
  run_best_effort config/smtp/01-write-service-smtp-reference.sh
  run_best_effort config/uptime-kuma/02-uptime-kuma-auto-config.sh
  run_best_effort config/pbs/01-pbs-backup-automation.sh
  run_required services/chia/01-chia-farmer-service-install.sh || return $?
}

run_full_install_pipeline(){
  clear || true
  cat <<'PIPE'
=========================================
 Homelab v2.4.7 - Guided full pipeline
=========================================
Bu seçenek mevcut mimariyi bozmaz; menüdeki scriptleri sırayla çağırır.

Akış:
  1) Bootstrap secrets/env
  2) Create Proxmox users
  12) Normalize Proxmox local storage (safe/register only)
  3) Install TrueNAS VM 101 + manual checkpoint

Sonra bilinçli manuel durak:
  - TrueNAS installer'ı VM console'dan manuel bitir
  - Router reservation önerisi: 02:23:14:00:01:01 -> 192.168.50.101
  - TrueNAS WebUI'den SSH'i aç

Devamında otomatik:
  4) TrueNAS postinstall + storage bootstrap + VM102-107 + VM110 PBS
  5) Prepare all Docker hosts
  6) Install core services
  7) Configure / repair basics
  8) Run all core config scripts
  9) SMTP / Uptime Kuma / Chia

Not: v2.4.7 Cloudflared auth erken Proxmox aşamasında yapılır; VM103 final aşaması sadece JSON credential kullanır.
PIPE
  echo
  read -r -p "Bu uzun pipeline başlasın mı? [y/N]: " start_ans
  [[ "$start_ans" =~ ^[Yy]$ ]] || { echo "İptal edildi."; return 0; }

  echo
  echo "==================== PHASE A: Proxmox hazırlık ===================="
  run_required bootstrap/00-bootstrap-secrets.sh || return $?
  run_early_cloudflared_prepare
  run_best_effort maintenance/health/hardware-preflight.sh
  run_required bootstrap/01-create-proxmox-users.sh || return $?
  HOMELAB_DESTRUCTIVE_STORAGE_RESET=1 run_required bootstrap/02-normalize-local-storage.sh || return $?

  echo
  echo "==================== PHASE B: TrueNAS VM 101 ===================="
  run_truenas_vm_and_checkpoint || return $?

  echo
  echo "==================== PHASE C: TrueNAS API/storage + VM102-107 + VM110 ===================="
  HOMELAB_FORCE_NEW_TRUENAS_API=1 ensure_truenas_api_ready || return $?
  run_required services/truenas/01-truenas-api-bootstrap-storage.sh || return $?
  run_required vm/102-docker-arr-vm-install.sh || return $?
  run_required vm/103-network-vm-install.sh || return $?
  run_required vm/104-nextcloud-vm-install.sh || return $?
  run_required vm/105-homeassistant-vm-install.sh || return $?
  run_required vm/106-media-ai-vm-install.sh || return $?
  run_required vm/107-chia-farmer-vm-install.sh || return $?
  run_required vm/110-pbs-backup-vm-install.sh || return $?

  echo
  echo "==================== PHASE D: Docker host hazırlığı ===================="
  run_required services/common/01-prepare-all-docker-hosts.sh || return $?

  echo
  echo "==================== PHASE E: Core service install ===================="
  run_core_services || return $?

  echo
  echo "==================== PHASE F: Basic repair/config ===================="
  run_repair_basics

  echo
  echo "==================== PHASE G: Phase 3 service config ===================="
  run_best_effort config/00-run-all-core-config.sh

  echo
  echo "==================== PHASE H: Phase 4 SMTP / Chia ===================="
  run_phase4 || return $?

  echo
  echo "==================== PHASE I: Final Cloudflared remote access ===================="
  run_final_cloudflared || return $?

  echo
  echo "==================== FINAL HEALTH CHECKS ===================="
  run_best_effort maintenance/health/vm-resource-audit.sh
  run_best_effort maintenance/health/full-health-check.sh
  run_best_effort maintenance/health/full-service-audit.sh

  echo
  echo "✅ Guided full pipeline tamamlandı."
  echo "Loglar: ${LOG_DIR:-/root/homelab-logs}"
}

while true; do
  clear || true
  cat <<'MENU'
=========================================
 Homelab v2.4.7 - Install Menu
=========================================
0) Guided full install pipeline (1→9 + final Cloudflared, TrueNAS manuel duraklı)
1) Bootstrap secrets/env
2) Create Proxmox users
3) Install TrueNAS VM 101 + manual checkpoint
4) Bootstrap TrueNAS storage + install all VMs except TrueNAS
5) Prepare all Docker hosts
6) Install core local services (Cloudflared auth yok)
7) Configure / repair basics
8) Phase 3 service configuration
9) Phase 4 Chia / SMTP
10) Maintenance menu
11) Additionals menu
12) Normalize Proxmox local storage (safe/register only)
13) Exit
14) Final Cloudflared remote access setup
15) Prepare Cloudflare Tunnel credentials early
16) DESTRUCTIVE fresh storage reset (wipe nvme-vm + nvme-vm-two)
MENU
  read -r -p "Seçim: " choice
  case "$choice" in
    0) run_full_install_pipeline ;;
    1) run bootstrap/00-bootstrap-secrets.sh ;;
    2) run bootstrap/01-create-proxmox-users.sh ;;
    3) run_truenas_vm_and_checkpoint ;;
    4)
      if ensure_truenas_api_ready; then
        run_required services/truenas/01-truenas-api-bootstrap-storage.sh || break
        run_required vm/102-docker-arr-vm-install.sh || break
        run_required vm/103-network-vm-install.sh || break
        run_required vm/104-nextcloud-vm-install.sh || break
        run_required vm/105-homeassistant-vm-install.sh || break
        run_required vm/106-media-ai-vm-install.sh || break
        run_required vm/107-chia-farmer-vm-install.sh || break
        run_required vm/110-pbs-backup-vm-install.sh || break
      else
        echo "❌ TrueNAS API hazır değil; VM bootstrap aşaması güvenli şekilde durduruldu."
      fi ;;
    5) run services/common/01-prepare-all-docker-hosts.sh ;;
    6) run_core_services ;;
    7) run_repair_basics ;;
    8) bash "$ROOT_DIR/menu/config-menu.sh" ;;
    9) run_phase4 ;;
    10) bash "$ROOT_DIR/menu/maintenance-menu.sh" ;;
    11) bash "$ROOT_DIR/menu/additionals-menu.sh" ;;
    12) run bootstrap/02-normalize-local-storage.sh ;;
    13) exit 0 ;;
    14) run_final_cloudflared ;;
    15) run_early_cloudflared_prepare ;;
    16) HOMELAB_DESTRUCTIVE_STORAGE_RESET=1 run bootstrap/02-normalize-local-storage.sh ;;
    *) echo "Geçersiz seçim"; sleep 2 ;;
  esac
  read -r -p "Devam için Enter..." _
done
