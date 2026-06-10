#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/env-loader.sh"
source "$SCRIPT_DIR/../utils/logging.sh"

start_log "create-proxmox-users"
require_root
load_all_env

create_linux_group() {
  local group_name="$1"
  local gid="$2"

  if getent group "$group_name" >/dev/null 2>&1; then
    echo "ℹ️ Linux group zaten mevcut: $group_name"
    return 0
  fi

  if getent group "$gid" >/dev/null 2>&1; then
    echo "⚠️ GID $gid zaten kullanımda; $group_name grubu varsayılan GID ile oluşturulacak."
    groupadd "$group_name"
  else
    groupadd -g "$gid" "$group_name"
  fi

  echo "✅ Linux group hazırlandı: $group_name"
}

create_linux_user() {
  local account="$1"
  local pass="$2"
  local uid="$3"
  local gid="$4"
  local shell="$5"

  [[ -n "$account" ]] || { echo "❌ account boş"; return 1; }
  [[ -n "$pass" ]] || { echo "❌ $account için password boş"; return 1; }
  [[ -n "$uid" ]] || { echo "❌ $account için UID boş"; return 1; }
  [[ -n "$gid" ]] || { echo "❌ $account için GID boş"; return 1; }
  [[ -n "$shell" ]] || { echo "❌ $account için shell boş"; return 1; }

  create_linux_group "$account" "$gid"

  if id "$account" >/dev/null 2>&1; then
    echo "ℹ️ Linux user zaten mevcut: $account"
  else
    if getent passwd "$uid" >/dev/null 2>&1; then
      echo "⚠️ UID $uid zaten kullanımda; $account varsayılan UID ile oluşturulacak."
      useradd -m -g "$account" -s "$shell" "$account"
    else
      useradd -m -u "$uid" -g "$account" -s "$shell" "$account"
    fi

    echo "✅ Linux user oluşturuldu: $account"
  fi

  echo "$account:$pass" | chpasswd
}

pve_user_exists() {
  local userid="$1"

  pveum user list 2>/dev/null \
    | awk 'NR > 1 {print $1}' \
    | grep -Fxq "$userid"
}

ensure_pve_user() {
  local account="$1"
  local pass="$2"
  local role="$3"
  local pve_user="${account}@pam"
  local err="/tmp/pveum-user-add-${account}.err"

  [[ -n "$account" ]] || { echo "❌ Proxmox account boş"; return 1; }
  [[ -n "$pass" ]] || { echo "❌ $account için Proxmox password boş"; return 1; }
  [[ -n "$role" ]] || { echo "❌ $account için Proxmox role boş"; return 1; }

  if pve_user_exists "$pve_user"; then
    echo "ℹ️ Proxmox user zaten mevcut: $pve_user — create atlandı."
  else
    rm -f "$err"

    if pveum user add "$pve_user" >"$err" 2>&1; then
      echo "✅ Proxmox user oluşturuldu: $pve_user"
    elif grep -Eiq "already exists|user .*exists|user '${pve_user}' already exists" "$err" 2>/dev/null || pve_user_exists "$pve_user"; then
      echo "ℹ️ Proxmox user zaten mevcut görünüyor: $pve_user — devam."
    else
      echo "❌ Proxmox user oluşturulamadı: $pve_user"
      cat "$err" 2>/dev/null || true
      return 1
    fi
  fi

  # Re-run repair: user zaten varsa bile password, enable state ve ACL/role tekrar doğrulanır.
  echo "$account:$pass" | chpasswd || true

  pveum user modify "$pve_user" --enable 1 >/dev/null 2>&1 || true
  pveum acl modify / -user "$pve_user" -role "$role"

  echo "✅ Proxmox ACL/role doğrulandı: $pve_user -> $role"
}

echo "👥 Linux + Proxmox kullanıcıları hazırlanıyor..."

create_linux_user "$MEDIA_USER" "$MEDIA_PASS" "$MEDIA_UID" "$MEDIA_GID" "/usr/sbin/nologin"
create_linux_user "$BACMASTER_USER" "$BACMASTER_PASS" "$BACMASTER_UID" "$BACMASTER_GID" "/bin/bash"
create_linux_user "$TULUMBA_USER" "$TULUMBA_PASS" "$TULUMBA_UID" "$TULUMBA_GID" "/bin/bash"
create_linux_user "$BACKUP_USER" "$BACKUP_PASS" "$BACKUP_UID" "$BACKUP_GID" "/bin/bash"

usermod -aG sudo "$BACMASTER_USER" || true
usermod -aG sudo "$TULUMBA_USER" || true

ensure_pve_user "$BACMASTER_USER" "$BACMASTER_PASS" "Administrator"
ensure_pve_user "$TULUMBA_USER" "$TULUMBA_PASS" "PVEAdmin"

echo "✅ Proxmox users tamam."
