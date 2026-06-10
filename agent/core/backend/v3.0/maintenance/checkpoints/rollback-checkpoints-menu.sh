#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "rollback-checkpoints"
MANAGED=(102 103 104 105 106 107 110)
SNAPS=(hl-vm-created hl-ubuntu-ready hl-docker-ready hl-services-installed hl-configured)
vm_exists(){ qm status "$1" >/dev/null 2>&1; }
vm_status(){ qm status "$1" 2>/dev/null | awk '{print $2}' || echo missing; }
stop_vm(){ local v="$1"; if vm_exists "$v" && [[ "$(vm_status "$v")" == running ]]; then qm shutdown "$v" --timeout 60 || qm stop "$v" || true; fi; }
confirm(){ local phrase="$1" msg="$2" ans; echo; echo "⚠️ $msg"; read -r -p "Devam için $phrase yaz: " ans; [[ "$ans" == "$phrase" ]]; }
status(){ echo; printf '%-6s %-24s %-10s\n' VMID Name Status; for v in 101 "${MANAGED[@]}"; do if vm_exists "$v"; then printf '%-6s %-24s %-10s\n' "$v" "$(qm config "$v" | awk -F': ' '/^name:/ {print $2; exit}')" "$(vm_status "$v")"; else printf '%-6s %-24s %-10s\n' "$v" missing -; fi; done; }
rollback_truenas_only(){ status; confirm ROLLBACK "VM102-107/110 silinecek. VM101 TrueNAS korunacak." || return 0; for v in "${MANAGED[@]}"; do vm_exists "$v" || continue; echo "🗑️ VM$v siliniyor"; qm unlock "$v" 2>/dev/null || true; stop_vm "$v"; qm destroy "$v" --purge 1 --destroy-unreferenced-disks 1 || qm destroy "$v" --purge 1 || true; done; for ip in 192.168.50.{102..107} 192.168.50.110; do ssh-keygen -R "$ip" >/dev/null 2>&1 || true; done; echo "✅ TrueNAS-only rollback tamam."; }
create_snap(){ local snap="$1"; status; confirm CHECKPOINT "VM102-107/110 için $snap snapshot alınacak." || return 0; for v in "${MANAGED[@]}"; do vm_exists "$v" || continue; if qm listsnapshot "$v" | awk '{print $2}' | grep -Fxq "$snap"; then qm delsnapshot "$v" "$snap" --force 1 || true; fi; echo "📸 VM$v -> $snap"; qm snapshot "$v" "$snap" --description "Homelab checkpoint $snap $(date -Is)"; done; }
list_snaps(){ for v in "${MANAGED[@]}"; do echo; echo "VM$v"; vm_exists "$v" && qm listsnapshot "$v" || echo missing; done; }
rollback_snap(){ list_snaps; echo; select snap in "${SNAPS[@]}" custom back; do case "$snap" in custom) read -r -p "Snapshot adı: " snap; break;; back) return 0;; "") echo invalid;; *) break;; esac; done; confirm ROLLBACK "VM102-107/110 $snap snapshot'ına dönecek." || return 0; for v in "${MANAGED[@]}"; do vm_exists "$v" || continue; qm listsnapshot "$v" | awk '{print $2}' | grep -Fxq "$snap" || { echo "❌ VM$v snapshot yok: $snap"; return 1; }; stop_vm "$v"; qm rollback "$v" "$snap"; done; read -r -p "VM102-107/110 başlatılsın mı? [y/N]: " a; [[ "$a" =~ ^[Yy]$ ]] && for v in "${MANAGED[@]}"; do qm start "$v" || true; done; }
while true; do clear || true; cat <<MENU
=========================================
 Homelab v2.4.7 - Rollback / Checkpoints
=========================================
1) Show VM status
2) Rollback to Proxmox + TrueNAS only
3) Create checkpoint: VM created
4) Create checkpoint: Ubuntu/SSH ready
5) Create checkpoint: Docker ready
6) Create checkpoint: Services installed
7) Create checkpoint: Configured
8) Rollback to checkpoint
9) List checkpoints
10) Back
MENU
read -r -p "Seçim: " c
case "$c" in
1) status;; 2) rollback_truenas_only;; 3) create_snap hl-vm-created;; 4) create_snap hl-ubuntu-ready;; 5) create_snap hl-docker-ready;; 6) create_snap hl-services-installed;; 7) create_snap hl-configured;; 8) rollback_snap;; 9) list_snaps;; 10) exit 0;; *) echo invalid;; esac
read -r -p "Devam için Enter..." _
done
