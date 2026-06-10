#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/utils/logging.sh"; start_log "uptime-kuma-auto-config"
USERS_ENV="/root/homelab-secrets/users.env"
[[ -f "$USERS_ENV" ]] || { echo "❌ users.env bulunamadı: $USERS_ENV"; exit 1; }
set -a; source "$USERS_ENV"; set +a
SSH_USER="${BACMASTER_USER:-bacmaster}"; SSH_PASS="${BACMASTER_PASS:-}"; KUMA_USER="${BACMASTER_USER:-bacmaster}"; KUMA_PASS="${BACMASTER_PASS:-}"
[[ -n "$SSH_PASS" && -n "$KUMA_PASS" ]] || { echo "❌ BACMASTER_PASS bulunamadı."; exit 1; }
apt update
apt install -y sshpass curl jq sqlite3 python3
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10)
shell_quote(){ printf '%q' "$1"; }
run_ssh(){ local ip="$1" tmp remote_cmd; tmp="$(mktemp)"; cat > "$tmp"; sshpass -p "$SSH_PASS" scp "${SSH_OPTS[@]}" "$tmp" "$SSH_USER@$ip:/tmp/homelab-kuma-config.sh" >/dev/null; remote_cmd="printf '%s\n' $(shell_quote "$SSH_PASS") | sudo -S -p '' env KUMA_USER=$(shell_quote "$KUMA_USER") KUMA_PASS=$(shell_quote "$KUMA_PASS") bash /tmp/homelab-kuma-config.sh"; sshpass -p "$SSH_PASS" ssh "${SSH_OPTS[@]}" "$SSH_USER@$ip" "$remote_cmd"; rm -f "$tmp"; }

echo; echo "📡 VM103 Uptime Kuma auto-config başlıyor..."
run_ssh 192.168.50.103 <<'REMOTE'
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
apt update >/dev/null
apt install -y curl jq sqlite3 python3 python3-bcrypt netcat-openbsd iputils-ping >/dev/null
cd /opt/homelab/uptime-kuma || { echo "❌ /opt/homelab/uptime-kuma yok"; exit 1; }
docker compose up -d uptime-kuma >/dev/null

# Uptime Kuma v2 needs UPTIME_KUMA_DB_TYPE=sqlite in compose env; otherwise it may stop at the WebUI DB picker.
if ! grep -q "UPTIME_KUMA_DB_TYPE" /opt/homelab/uptime-kuma/.env 2>/dev/null && ! grep -q "UPTIME_KUMA_DB_TYPE" docker-compose.yml 2>/dev/null; then
  echo "⚠️ UPTIME_KUMA_DB_TYPE görülmedi; SQLite otomatik seçim için compose/env düzeltmesi deneniyor."
  sed -i '/UPTIME_KUMA_SQLITE_SINGLE_CONNECTION/i\      - UPTIME_KUMA_DB_TYPE=sqlite' docker-compose.yml || true
  docker compose up -d uptime-kuma >/dev/null || true
fi

echo "⏳ Uptime Kuma SQLite DB bekleniyor..."
DB_FILE=""
for i in {1..120}; do
  for db in /opt/homelab/uptime-kuma/data/kuma.db /opt/homelab/uptime-kuma/kuma.db; do
    [[ -f "$db" ]] && { DB_FILE="$db"; break; }
  done
  [[ -n "$DB_FILE" ]] && break
  sleep 2
done
[[ -n "$DB_FILE" ]] || { echo "❌ Uptime Kuma DB bulunamadı. Büyük olasılıkla v2 DB seçim ekranında takıldı; UPTIME_KUMA_DB_TYPE=sqlite kontrol edilmeli."; find /opt/homelab/uptime-kuma -maxdepth 4 -type f | sort || true; docker logs hb-uptime-kuma --tail=120 || true; exit 1; }
echo "✅ DB bulundu: $DB_FILE"

docker compose stop uptime-kuma >/dev/null || true
cp "$DB_FILE" "$DB_FILE.backup.$(date +%Y%m%d-%H%M%S)" || true
export DB_FILE

# v2.4.6: Optional-service monitors should not stay active-red when the VM was not created.
VM106_REACHABLE=0
VM107_REACHABLE=0
if ping -c1 -W1 192.168.50.106 >/dev/null 2>&1 || nc -z -w2 192.168.50.106 22 >/dev/null 2>&1; then VM106_REACHABLE=1; fi
if ping -c1 -W1 192.168.50.107 >/dev/null 2>&1 || nc -z -w2 192.168.50.107 22 >/dev/null 2>&1; then VM107_REACHABLE=1; fi
export VM106_REACHABLE VM107_REACHABLE
echo "VM106_REACHABLE=$VM106_REACHABLE VM107_REACHABLE=$VM107_REACHABLE"

python3 <<'PY' 
import os, sqlite3, bcrypt
from datetime import datetime, timezone

db=os.environ['DB_FILE']; username=os.environ['KUMA_USER']; password=os.environ['KUMA_PASS']
now=datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')
pw_hash=bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()
vm106_reachable=os.environ.get("VM106_REACHABLE","0") == "1"
vm107_reachable=os.environ.get("VM107_REACHABLE","0") == "1"

# tuple: name,type,url,host,port,ignore_tls,active,optional_group
monitors=[
 ('Proxmox','http','https://192.168.50.100:8006','',None,1,1,'core'),
 ('TrueNAS','http','http://192.168.50.101','',None,0,1,'core'),
 ('qBittorrent','http','http://192.168.50.102:8080','',None,0,1,'core'),
 ('Sonarr','http','http://192.168.50.102:8989','',None,0,1,'core'),
 ('Radarr','http','http://192.168.50.102:7878','',None,0,1,'core'),
 ('Bazarr','http','http://192.168.50.102:6767','',None,0,1,'core'),
 ('Prowlarr','http','http://192.168.50.102:9696','',None,0,1,'core'),
 ('Seerr','http','http://192.168.50.102:5055','',None,0,1,'core'),
 ('Nextcloud','http','http://192.168.50.104:8080/status.php','',None,0,1,'core'),
 ('Home Assistant','http','http://192.168.50.105:8123','',None,0,1,'core'),
 ('Open WebUI','http','http://192.168.50.106:3000','',None,0,1 if vm106_reachable else 0,'vm106'),
 ('Ollama API','http','http://192.168.50.106:11434','',None,0,1 if vm106_reachable else 0,'vm106'),
 ('Jellyfin','http','http://192.168.50.106:8096','',None,0,1 if vm106_reachable else 0,'vm106'),
 ('Immich','http','http://192.168.50.106:2283','',None,0,1 if vm106_reachable else 0,'vm106'),
 ('Lidarr','http','http://192.168.50.106:8686','',None,0,1 if vm106_reachable else 0,'vm106'),
 ('PBS Backup','http','https://192.168.50.110:8007','',None,1,1,'core'),
 ('Chia Daemon','port','','192.168.50.107',55400,0,0,'vm107'),
]
conn=sqlite3.connect(db); conn.row_factory=sqlite3.Row; cur=conn.cursor()
def table_exists(t): cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?",(t,)); return cur.fetchone() is not None
def cols(t): cur.execute(f'PRAGMA table_info("{t}")'); return [r['name'] for r in cur.fetchall()]
def set_col(data, c, k, v):
    if k in c: data[k]=v
if not table_exists('user'): raise SystemExit('user tablosu yok')
uc=cols('user'); cur.execute('SELECT id FROM "user" WHERE username=? LIMIT 1',(username,)); row=cur.fetchone()
if row:
    uid=row['id']; data={}; set_col(data,uc,'password',pw_hash); set_col(data,uc,'active',1); set_col(data,uc,'timezone','Europe/Istanbul')
    if data: cur.execute(f'UPDATE "user" SET {",".join([k+"=?" for k in data])} WHERE id=?', list(data.values())+[uid])
else:
    data={}; set_col(data,uc,'username',username); set_col(data,uc,'password',pw_hash); set_col(data,uc,'active',1); set_col(data,uc,'timezone','Europe/Istanbul')
    cur.execute(f'INSERT INTO "user" ({",".join(data.keys())}) VALUES ({",".join(["?"]*len(data))})', list(data.values())); uid=cur.lastrowid
print(f'✅ Admin hazır: {username} / user_id={uid}')
if not table_exists('monitor'): raise SystemExit('monitor tablosu yok')
mc=cols('monitor')
for name,mtype,url,host,port,ignore_tls,desired_active,group in monitors:
    cur.execute('SELECT id FROM "monitor" WHERE name=? AND user_id=? LIMIT 1',(name,uid)); existing=cur.fetchone()
    data={}
    # v2.4.6: VM106/VM107 optional monitors are disabled if the VM is absent, preventing misleading red dashboards.
    active = int(desired_active)
    base_fields=[('user_id',uid),('name',name),('type',mtype),('url',url),('hostname',host),('port',port),('method','GET'),('interval',60),('retryInterval',60),('maxretries',3),('active',active),('upsideDown',0),('maxredirects',10),('accepted_statuscodes','["200-299","300-399","401","403"]'),('created_date',now),('weight',2000)]
    # Uptime Kuma v1/v2 schema names differ. Set every supported TLS-ignore field.
    tls_fields=['ignoreTls','ignore_tls','tlsIgnore','tls_ignore','skipTlsVerify','skip_tls_verify']
    for k,v in base_fields: set_col(data,mc,k,v)
    for k in tls_fields: set_col(data,mc,k,ignore_tls)
    if existing:
        cur.execute(f'UPDATE "monitor" SET {",".join([k+"=?" for k in data])} WHERE id=?', list(data.values())+[existing['id']]); print(f'🔁 Monitor güncellendi: {name}')
    else:
        cur.execute(f'INSERT INTO "monitor" ({",".join(data.keys())}) VALUES ({",".join(["?"]*len(data))})', list(data.values())); print(f'✅ Monitor eklendi: {name}')
if 'user_id' in mc: cur.execute('DELETE FROM "monitor" WHERE (user_id IS NULL OR user_id="")')
conn.commit()
print(f"ℹ️ Optional monitor state: VM106 reachable={vm106_reachable}, VM107 reachable={vm107_reachable}")
# Validate TLS ignore for Proxmox/PBS in whatever columns exist.
for mon in ("Proxmox","PBS Backup"):
    cur.execute('SELECT * FROM "monitor" WHERE name=? AND user_id=? LIMIT 1',(mon,uid))
    row=cur.fetchone()
    if row:
        vals={k: row[k] for k in row.keys() if k in ["ignoreTls","ignore_tls","tlsIgnore","tls_ignore","skipTlsVerify","skip_tls_verify"]}
        print(f"TLS ignore validate {mon}: {vals}")
conn.close()
PY
chown -R 1000:1000 "$(dirname "$DB_FILE")" || true
docker compose up -d uptime-kuma >/dev/null
for i in {1..60}; do curl -fsS http://127.0.0.1:3001 >/dev/null 2>&1 && { echo "✅ Uptime Kuma hazır."; break; }; sleep 2; done
echo "✅ Uptime Kuma admin + monitors auto-config tamamlandı. Login: $KUMA_USER / BACMASTER_PASS"
echo "ℹ️ Chia Daemon monitor disabled tutulur; Chia daemon varsayılan olarak sadece VM107 localhost üzerinde dinler."
REMOTE
