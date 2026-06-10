#!/usr/bin/env bash
set -Eeuo pipefail

# Run this on the Proxmox host as root.
#
# Bacmaster's NAS TrueNAS v8 topbar cleanup:
# - removes the leftover large "S" from the original TrueNAS wordmark
# - keeps the Bacmaster's NAS top-left overlay
# - updates cache-busting query strings to v8
# - leaves login wallpaper and previous v7 branding intact
#
# This only touches TrueNAS WebUI static branding files.

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
echo "==> Bacmaster's NAS v8 topbar cleanup"

remote_sudo <<'REMOTE'
set -Eeuo pipefail

WEBUI="/usr/share/truenas/webui"
INDEX="$WEBUI/index.html"
BRAND_DIR="$WEBUI/bacmasters-brand"
JS="$BRAND_DIR/bacmasters-nas-branding.js"
CSS="$BRAND_DIR/bacmasters-nas-branding.css"
STATE="/tmp/bacmasters-nas-v8-remounted-ro.txt"

: > "$STATE"

if [[ ! -f "$INDEX" ]]; then
  echo "ERROR: index.html not found: $INDEX"
  exit 10
fi

if [[ ! -f "$JS" || ! -f "$CSS" ]]; then
  echo "ERROR: Existing Bacmaster branding files not found."
  echo "Run v7 first, then run this v8 cleanup."
  exit 11
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

if ! touch "$WEBUI/.bacmasters-v8-write-test" 2>/dev/null; then
  echo "ERROR: WebUI is still not writable."
  exit 20
fi
rm -f "$WEBUI/.bacmasters-v8-write-test"

backup="/root/bacmasters-nas-webui-backups/v8-topbar-cleanup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup"
cp -a "$INDEX" "$backup/index.html"
cp -a "$JS" "$backup/bacmasters-nas-branding.js"
cp -a "$CSS" "$backup/bacmasters-nas-branding.css"
echo "Backup: $backup"

# Update index.html cache busting to v8 while keeping the existing single branding block.
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
<link rel="stylesheet" href="/ui/bacmasters-brand/bacmasters-nas-branding.css?v=bacmasters-nas-v8">
<script defer src="/ui/bacmasters-brand/bacmasters-nas-branding.js?v=bacmasters-nas-v8"></script>
<!-- BACMASTERS_NAS_BRANDING_END -->'''

if "</head>" in s:
    s = s.replace("</head>", inject + "\n</head>", 1)
else:
    s = inject + "\n" + s

p.write_text(s)
PY

# Append v8 CSS override. Remove previous v8 block if present.
python3 - "$CSS" <<'PY'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
s = p.read_text(errors="ignore")
s = re.sub(
    r'/\* BACMASTERS_NAS_V8_TOPBAR_CLEANUP_START \*/.*?/\* BACMASTERS_NAS_V8_TOPBAR_CLEANUP_END \*/',
    '',
    s,
    flags=re.S,
)

patch = r'''
/* BACMASTERS_NAS_V8_TOPBAR_CLEANUP_START */
/*
  Covers the remaining right edge of the original TrueNAS wordmark.
  pointer-events:none keeps the hamburger/menu area usable even if the overlay is wider.
*/
#bacmasters-nas-topbar-brand {
  width: 224px !important;
  height: 48px !important;
  left: 0 !important;
  top: 0 !important;
  padding: 5px 80px 5px 14px !important;
  justify-content: flex-start !important;
  background: #101113 !important;
  pointer-events: none !important;
}

#bacmasters-nas-topbar-brand::after {
  content: "" !important;
  position: absolute !important;
  top: 0 !important;
  right: 0 !important;
  width: 86px !important;
  height: 48px !important;
  display: block !important;
  background: #101113 !important;
  z-index: 0 !important;
}

#bacmasters-nas-topbar-brand img {
  position: relative !important;
  z-index: 1 !important;
  width: 144px !important;
  max-height: 34px !important;
  object-fit: contain !important;
}

/* Hide any original TrueNAS wordmark element that is still sitting underneath the overlay. */
.bacmasters-nas-hide-original-topbar-brand {
  visibility: hidden !important;
  opacity: 0 !important;
  pointer-events: none !important;
}
/* BACMASTERS_NAS_V8_TOPBAR_CLEANUP_END */
'''
p.write_text(s.rstrip() + "\n\n" + patch + "\n")
PY

# Append a tiny JS cleanup helper. Remove previous v8 helper if present.
python3 - "$JS" <<'PY'
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
s = p.read_text(errors="ignore")
s = re.sub(
    r'/\* BACMASTERS_NAS_V8_TOPBAR_CLEANUP_START \*/.*?/\* BACMASTERS_NAS_V8_TOPBAR_CLEANUP_END \*/',
    '',
    s,
    flags=re.S,
)

patch = r'''
/* BACMASTERS_NAS_V8_TOPBAR_CLEANUP_START */
(function () {
  'use strict';

  function isLoginRoute() {
    var path = String(window.location.pathname || '').toLowerCase();
    return path.indexOf('signin') !== -1 || path.indexOf('login') !== -1;
  }

  function looksLikeOriginalTrueNasBrand(el) {
    if (!el || el.id === 'bacmasters-nas-topbar-brand') return false;
    if (el.closest && el.closest('#bacmasters-nas-topbar-brand')) return false;

    var text = String(el.innerText || el.textContent || '').toLowerCase();
    var attrs = '';
    if (el.getAttribute) {
      attrs = [
        'title', 'aria-label', 'alt', 'class', 'id', 'src', 'href', 'xlink:href'
      ].map(function (a) { return el.getAttribute(a) || ''; }).join(' ').toLowerCase();
    }

    return text.indexOf('truenas') !== -1 ||
           attrs.indexOf('truenas') !== -1 ||
           attrs.indexOf('ix-logo') !== -1;
  }

  function hasMenuButton(el) {
    if (!el || !el.querySelector) return false;
    var hay = String(el.innerText || '') + ' ' + String(el.getAttribute && (el.getAttribute('aria-label') || '') || '');
    if (/menu|hamburger/i.test(hay)) return true;
    return !!el.querySelector('[aria-label*="menu" i], [title*="menu" i], button, [role="button"]');
  }

  function hideOriginalTopbarBrand() {
    if (isLoginRoute() || !document.body) return;

    var all = Array.prototype.slice.call(document.body.querySelectorAll('a, div, span, svg, img, ix-logo, ix-icon'));
    var vw = Math.max(document.documentElement.clientWidth || 0, window.innerWidth || 0);

    all.forEach(function (el) {
      if (!el || !el.getBoundingClientRect) return;

      var r = el.getBoundingClientRect();
      if (r.top < -2 || r.top > 58) return;
      if (r.left < -2 || r.left > 232) return;
      if (r.width < 14 || r.height < 10) return;
      if (r.right > Math.min(250, vw * 0.35)) return;
      if (hasMenuButton(el)) return;

      if (looksLikeOriginalTrueNasBrand(el)) {
        el.classList.add('bacmasters-nas-hide-original-topbar-brand');
      }
    });
  }

  function ensureOverlaySize() {
    var brand = document.getElementById('bacmasters-nas-topbar-brand');
    if (!brand) return;
    brand.style.width = '224px';
    brand.style.pointerEvents = 'none';
  }

  function run() {
    hideOriginalTopbarBrand();
    ensureOverlaySize();
  }

  var count = 0;
  var timer = setInterval(function () {
    count += 1;
    run();
    if (count >= 120) clearInterval(timer);
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
      characterData: true,
      attributes: true,
      attributeFilter: ['class', 'style', 'title', 'aria-label', 'alt']
    });
  }
})();
 /* BACMASTERS_NAS_V8_TOPBAR_CLEANUP_END */
'''
p.write_text(s.rstrip() + "\n\n" + patch + "\n")
PY

chmod 0644 "$INDEX" "$JS" "$CSS"

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
echo "OK: Bacmaster's NAS v8 topbar cleanup applied."
REMOTE

echo
echo "==> Proxmox-side HTTP checks"
curl -fsSI "http://${TRUENAS_IP}/ui/bacmasters-brand/bacmasters-nas-branding.js?v=bacmasters-nas-v8" | head -5 || true
curl -fsSI "http://${TRUENAS_IP}/ui/bacmasters-brand/bacmasters-nas-branding.css?v=bacmasters-nas-v8" | head -5 || true

echo
echo "✅ Done."
echo "Open a NEW incognito/private window or press Ctrl+F5 twice:"
echo "  http://${TRUENAS_IP}/ui/dashboard?bacmasters_v8=1"
