#!/usr/bin/env bash
set -Eeuo pipefail

# Run this on the Proxmox host as root.
#
# Bacmaster's NAS TrueNAS v9 login wallpaper force-fix:
# - keeps existing v7/v8 branding
# - forces the login background layer to reappear after cache/route changes
# - does not touch pools, datasets, services, middleware settings, or TrueNAS config
#
# Expected existing asset:
#   /usr/share/truenas/webui/bacmasters-brand/bacmasters-nas-login-background.png

TRUENAS_IP="${TRUENAS_IP:-192.168.50.101}"

source /root/homelab-secrets/truenas-login.env 2>/dev/null || true

TRUENAS_USER="${TRUENAS_SSH_USER:-truenas_admin}"
TRUENAS_PASS="${TRUENAS_SSH_PASS:-}"

if [[ -z "${TRUENAS_PASS}" ]]; then
  echo "TrueNAS SSH/sudo password gerekli."
  read -rsp "TrueNAS password: " TRUENAS_PASS
  echo
fi

if ! command -v sshpass >/dev/null 2>&1; then
  echo "sshpass yok; kuruluyor..."
  apt-get update
  apt-get install -y sshpass
fi

remote_sudo() {
  {
    printf '%s\n' "$TRUENAS_PASS"
    cat
  } | SSHPASS="$TRUENAS_PASS" sshpass -e ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$TRUENAS_USER@$TRUENAS_IP" \
    "sudo -S -p '' bash -s"
}

echo
echo "==> Bacmaster's NAS v9 login wallpaper force-fix"

remote_sudo <<'REMOTE'
set -Eeuo pipefail

WEBUI="/usr/share/truenas/webui"
INDEX="$WEBUI/index.html"
BRAND_DIR="$WEBUI/bacmasters-brand"
JS="$BRAND_DIR/bacmasters-nas-branding.js"
CSS="$BRAND_DIR/bacmasters-nas-branding.css"
BG="$BRAND_DIR/bacmasters-nas-login-background.png"
STATE="/tmp/bacmasters-nas-v9-remounted-ro.txt"

: > "$STATE"

if [[ ! -f "$INDEX" ]]; then
  echo "ERROR: index.html not found: $INDEX"
  exit 10
fi

if [[ ! -f "$JS" || ! -f "$CSS" ]]; then
  echo "ERROR: Existing Bacmaster branding JS/CSS not found."
  echo "Run v7/v8 branding first, then run this v9 wallpaper fix."
  exit 11
fi

if [[ ! -f "$BG" ]]; then
  echo "ERROR: Background image not found: $BG"
  echo "Run v7 branding first, then run this v9 wallpaper fix."
  exit 12
fi

mapfile -t MPS < <(
  for p in / /usr /usr/share "$WEBUI"; do
    findmnt -T "$p" -no TARGET 2>/dev/null || true
  done | awk 'NF && !seen[$0]++'
)

for mp in "${MPS[@]}"; do
  opts="$(findmnt -no OPTIONS "$mp" 2>/dev/null || true)"
  if echo ",$opts," | grep -q ',ro,'; then
    echo "Remount RW: $mp"
    if mount -o remount,rw "$mp"; then
      echo "$mp" >> "$STATE"
    else
      echo "WARN: remount rw failed for $mp"
    fi
  fi
done

if ! touch "$WEBUI/.bacmasters-v9-write-test" 2>/dev/null; then
  echo "ERROR: WebUI is still not writable."
  exit 20
fi
rm -f "$WEBUI/.bacmasters-v9-write-test"

backup="/root/bacmasters-nas-webui-backups/v9-wallpaper-fix-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup"
cp -a "$INDEX" "$backup/index.html"
cp -a "$JS" "$backup/bacmasters-nas-branding.js"
cp -a "$CSS" "$backup/bacmasters-nas-branding.css"
echo "Backup: $backup"

# Update index.html cache busting to v9.
python3 - "$INDEX" <<'PY'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
s = p.read_text(errors="ignore")
s = re.sub(
    r'\n?<!-- BACMASTERS_NAS_BRANDING_START -->.*?<!-- BACMASTERS_NAS_BRANDING_END -->\n?',
    '\n',
    s,
    flags=re.S,
)

inject = '''<!-- BACMASTERS_NAS_BRANDING_START -->
<link rel="stylesheet" href="/ui/bacmasters-brand/bacmasters-nas-branding.css?v=bacmasters-nas-v9">
<script defer src="/ui/bacmasters-brand/bacmasters-nas-branding.js?v=bacmasters-nas-v9"></script>
<!-- BACMASTERS_NAS_BRANDING_END -->'''

if "</head>" in s:
    s = s.replace("</head>", inject + "\n</head>", 1)
else:
    s = inject + "\n" + s

p.write_text(s)
PY

# Append v9 CSS override. Remove previous v9 block if present.
python3 - "$CSS" <<'PY'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
s = p.read_text(errors="ignore")
s = re.sub(
    r'/\* BACMASTERS_NAS_V9_WALLPAPER_FORCE_START \*/.*?/\* BACMASTERS_NAS_V9_WALLPAPER_FORCE_END \*/',
    '',
    s,
    flags=re.S,
)

patch = r'''
/* BACMASTERS_NAS_V9_WALLPAPER_FORCE_START */
/*
  Force login wallpaper visibility even when TrueNAS route/cache changes
  leave the body background hidden behind Angular containers.
*/
body.bacmasters-nas-login {
  background: #02070e !important;
  background-color: #02070e !important;
}

body.bacmasters-nas-login::before {
  content: "" !important;
  position: fixed !important;
  inset: 0 !important;
  z-index: 0 !important;
  pointer-events: none !important;
  display: block !important;
  opacity: 1 !important;
  background:
    linear-gradient(rgba(0, 0, 0, 0.08), rgba(0, 0, 0, 0.40)),
    url('/ui/bacmasters-brand/bacmasters-nas-login-background.png?v=bacmasters-nas-v9') center center / cover no-repeat fixed !important;
  filter: saturate(1.12) contrast(1.05) !important;
}

#bacmasters-nas-page-bg {
  display: block !important;
  position: fixed !important;
  inset: 0 !important;
  z-index: 0 !important;
  pointer-events: none !important;
  opacity: 1 !important;
  background:
    linear-gradient(rgba(0, 0, 0, 0.08), rgba(0, 0, 0, 0.40)),
    url('/ui/bacmasters-brand/bacmasters-nas-login-background.png?v=bacmasters-nas-v9') center center / cover no-repeat fixed !important;
  filter: saturate(1.12) contrast(1.05) !important;
}

body.bacmasters-nas-login app-root,
body.bacmasters-nas-login ix-root,
body.bacmasters-nas-login .bacmasters-nas-transparent-bg {
  background: transparent !important;
  background-color: transparent !important;
}

body.bacmasters-nas-login app-root,
body.bacmasters-nas-login ix-root,
body.bacmasters-nas-login > *:not(#bacmasters-nas-page-bg) {
  position: relative !important;
  z-index: 1 !important;
}
/* BACMASTERS_NAS_V9_WALLPAPER_FORCE_END */
'''
p.write_text(s.rstrip() + "\n\n" + patch + "\n")
PY

# Append v9 JS route/layer helper. Remove previous v9 block if present.
python3 - "$JS" <<'PY'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
s = p.read_text(errors="ignore")
s = re.sub(
    r'/\* BACMASTERS_NAS_V9_WALLPAPER_FORCE_START \*/.*?/\* BACMASTERS_NAS_V9_WALLPAPER_FORCE_END \*/',
    '',
    s,
    flags=re.S,
)

patch = r'''
/* BACMASTERS_NAS_V9_WALLPAPER_FORCE_START */
(function () {
  'use strict';

  var BG = "/ui/bacmasters-brand/bacmasters-nas-login-background.png?v=bacmasters-nas-v9";

  function isLoginRoute() {
    var path = String(window.location.pathname || '').toLowerCase();
    return path.indexOf('signin') !== -1 || path.indexOf('login') !== -1;
  }

  function ensureLoginWallpaper() {
    if (!document.body) return;

    var login = isLoginRoute();
    document.body.classList.toggle('bacmasters-nas-login', login);

    var layer = document.getElementById('bacmasters-nas-page-bg');

    if (!login) {
      if (layer && layer.parentNode) layer.parentNode.removeChild(layer);
      return;
    }

    if (!layer) {
      layer = document.createElement('div');
      layer.id = 'bacmasters-nas-page-bg';
      layer.setAttribute('aria-hidden', 'true');
      document.body.insertBefore(layer, document.body.firstChild);
    }

    layer.style.cssText = [
      'position:fixed',
      'inset:0',
      'z-index:0',
      'pointer-events:none',
      'display:block',
      'opacity:1',
      'background:linear-gradient(rgba(0,0,0,.08),rgba(0,0,0,.40)),url("' + BG + '") center center / cover no-repeat fixed',
      'filter:saturate(1.12) contrast(1.05)'
    ].join(';') + ';';

    // Make route-level full-screen containers transparent so the wallpaper is visible.
    var vw = Math.max(document.documentElement.clientWidth || 0, window.innerWidth || 0);
    var vh = Math.max(document.documentElement.clientHeight || 0, window.innerHeight || 0);
    var els = Array.prototype.slice.call(document.body.querySelectorAll('app-root, ix-root, div, main, section')).slice(0, 900);

    els.forEach(function (el) {
      if (!el || el.id === 'bacmasters-nas-page-bg') return;
      if (el.querySelector && el.querySelector('input[type="password"]')) return;

      var r = el.getBoundingClientRect && el.getBoundingClientRect();
      if (!r) return;

      if (r.width >= vw * 0.70 && r.height >= vh * 0.70) {
        el.classList.add('bacmasters-nas-transparent-bg');
        el.style.backgroundColor = 'transparent';
      }
    });
  }

  function run() {
    try {
      ensureLoginWallpaper();
    } catch (err) {
      console.warn('[Bacmaster NAS branding] v9 wallpaper helper skipped:', err);
    }
  }

  var count = 0;
  var timer = setInterval(function () {
    count += 1;
    run();
    if (count >= 180) clearInterval(timer);
  }, 500);

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', run);
  } else {
    run();
  }

  window.addEventListener('load', run);
  window.addEventListener('hashchange', run);
  window.addEventListener('popstate', run);

  if (window.MutationObserver && document.body) {
    new MutationObserver(function () { setTimeout(run, 100); }).observe(document.body, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['class', 'style']
    });
  }
})();
/* BACMASTERS_NAS_V9_WALLPAPER_FORCE_END */
'''
p.write_text(s.rstrip() + "\n\n" + patch + "\n")
PY

chmod 0644 "$INDEX" "$JS" "$CSS" "$BG"

echo
echo "Injected lines:"
grep -n "bacmasters-brand" "$INDEX" || true

echo
echo "Reload nginx"
systemctl reload nginx 2>/dev/null || systemctl restart nginx 2>/dev/null || true

echo
echo "Local URL checks from TrueNAS:"
curl -fsSI http://127.0.0.1/ui/bacmasters-brand/bacmasters-nas-branding.js | head -5 || true
curl -fsSI http://127.0.0.1/ui/bacmasters-brand/bacmasters-nas-branding.css | head -5 || true
curl -fsSI http://127.0.0.1/ui/bacmasters-brand/bacmasters-nas-login-background.png | head -5 || true

echo
if [[ -s "$STATE" ]]; then
  tac "$STATE" | while read -r mp; do
    [[ -z "$mp" ]] && continue
    echo "Remount RO: $mp"
    mount -o remount,ro "$mp" 2>/dev/null || echo "WARN: could not remount RO: $mp"
  done
fi

echo
echo "Mountpoints after:"
for p in / /usr /usr/share "$WEBUI"; do
  findmnt -T "$p" -no TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null || true
done | awk '!seen[$0]++'

echo
echo "OK: Bacmaster's NAS v9 login wallpaper force-fix applied."
REMOTE

echo
echo "==> Proxmox-side HTTP checks"
curl -fsSI "http://${TRUENAS_IP}/ui/bacmasters-brand/bacmasters-nas-branding.js?v=bacmasters-nas-v9" | head -5 || true
curl -fsSI "http://${TRUENAS_IP}/ui/bacmasters-brand/bacmasters-nas-branding.css?v=bacmasters-nas-v9" | head -5 || true
curl -fsSI "http://${TRUENAS_IP}/ui/bacmasters-brand/bacmasters-nas-login-background.png?v=bacmasters-nas-v9" | head -5 || true

echo
echo "✅ Done."
echo "Open a NEW incognito/private window or press Ctrl+F5 twice:"
echo "  http://${TRUENAS_IP}/ui/signin?bacmasters_v9=1"
