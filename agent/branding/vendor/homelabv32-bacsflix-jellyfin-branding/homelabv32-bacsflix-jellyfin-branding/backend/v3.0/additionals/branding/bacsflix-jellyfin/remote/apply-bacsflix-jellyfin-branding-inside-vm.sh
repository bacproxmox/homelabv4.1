#!/usr/bin/env bash
set -Eeuo pipefail

MODE="${1:-apply}"
case "$MODE" in
  apply|restore|status) ;;
  *) echo "Usage: $0 apply|restore|status"; exit 2 ;;
esac

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSET_DIR="$BASE_DIR/assets"
BRAND_ROOT="/opt/homelab/jellyfin/branding/bacsflix"
BACKUP_ROOT="$BRAND_ROOT/backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
WORK_DIR="$(mktemp -d /tmp/bacsflix-jellyfin-v32.XXXXXX)"
CACHE_BUST="20260603v32"

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

log() { echo "🎬 $*"; }
warn() { echo "⚠️  $*"; }
fail() { echo "❌ $*"; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || fail "$1 bulunamadı"; }
need_asset() { [[ -f "$ASSET_DIR/$1" ]] || fail "Asset eksik: $ASSET_DIR/$1"; }

need_cmd docker
need_cmd python3
need_asset bacsflix-logo-wallpaper.png
need_asset bacsflix-logo-transparent.png
need_asset bacsflix-icon.png
need_asset bacsflix-wordmark-tight.png
need_asset favicon.png
need_asset bacmaster-logo.png

find_container() {
  local hint="${JELLYFIN_CONTAINER:-}"
  if [[ -n "$hint" ]] && docker ps -a --format '{{.Names}}' | grep -Fxq "$hint"; then
    echo "$hint"; return 0
  fi
  docker ps -a --format '{{.Names}}' \
    | grep -Ei '(^hb-jellyfin$|^jellyfin$|jellyfin)' \
    | head -n1
}

CONTAINER="$(find_container || true)"
[[ -n "$CONTAINER" ]] || fail "Jellyfin container bulunamadı. JELLYFIN_CONTAINER=container_adi ile tekrar deneyebilirsin."

if ! docker ps --format '{{.Names}}' | grep -Fxq "$CONTAINER"; then
  log "Container kapalı görünüyor, başlatılıyor: $CONTAINER"
  docker start "$CONTAINER" >/dev/null
  sleep 3
fi

find_webroot() {
  local c="$1"
  local p
  for p in \
    /usr/share/jellyfin/web \
    /jellyfin/jellyfin-web \
    /app/jellyfin-web \
    /opt/jellyfin/web \
    /web; do
    if docker exec "$c" sh -lc "test -f '$p/index.html'" >/dev/null 2>&1; then
      echo "$p"; return 0
    fi
  done
  local found
  found="$(docker exec "$c" sh -lc "find /usr/share /app /opt /jellyfin -maxdepth 5 -type f -name index.html 2>/dev/null | grep -Ei '/(web|jellyfin-web)/index.html' | head -n1" || true)"
  if [[ -n "$found" ]]; then
    dirname "$found"
  fi
}

WEBROOT="$(find_webroot "$CONTAINER" || true)"
[[ -n "$WEBROOT" ]] || fail "Jellyfin web root bulunamadı. Container içinde index.html yolu tespit edilemedi."

mkdir -p "$BACKUP_ROOT"

status() {
  echo
  echo "Bacsflix Jellyfin branding status"
  echo "----------------------------------"
  echo "Version   : v3.2 final red cinema theme"
  echo "Container : $CONTAINER"
  echo "Web root  : $WEBROOT"
  local marker="no"
  if docker exec "$CONTAINER" sh -lc "grep -q 'bacsflix-brand-loader-start' '$WEBROOT/index.html'" >/dev/null 2>&1; then marker="yes"; fi
  echo "Injected  : $marker"
  local assets="no"
  if docker exec "$CONTAINER" sh -lc "test -f '$WEBROOT/bacsflix-brand/bacsflix-brand.js' && test -f '$WEBROOT/bacsflix-brand/bacsflix-brand.css'" >/dev/null 2>&1; then assets="yes"; fi
  echo "Assets    : $assets"
  echo "Backups   : $BACKUP_ROOT"
  local latest
  latest="$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -n1 || true)"
  echo "Latest    : ${latest:-none}"
  echo
}

write_brand_files() {
  cat > "$WORK_DIR/bacsflix-brand.css" <<'CSS'
/* Homelab v3.2 Bacsflix private Jellyfin branding overlay. Reapply after Jellyfin container/web updates. */
:root {
  --bacsflix-red: #e50914;
  --bacsflix-red-hot: #ff1f2b;
  --bacsflix-red-dark: #650006;
  --bacsflix-panel: rgba(10, 8, 9, .82);
  --bacsflix-black: #050505;
  --bacsflix-card: rgba(18, 13, 14, .92);
}

html, body {
  background: #050505 !important;
}

body.bacsflix-branded {
  background:
    radial-gradient(circle at 26% 0%, rgba(229, 9, 20, .13), rgba(0,0,0,0) 32%),
    radial-gradient(circle at 80% 16%, rgba(120, 0, 8, .13), rgba(0,0,0,0) 28%),
    linear-gradient(180deg, #0c0708 0%, #050505 40%, #030303 100%) !important;
}

body.bacsflix-login-active {
  background:
    radial-gradient(circle at 50% 43%, rgba(229,9,20,.22), rgba(0,0,0,0) 35%),
    linear-gradient(90deg, #020203 0%, #070506 42%, #020203 100%) !important;
}

#bacsflix-login-bg {
  display: none;
  position: fixed;
  inset: 0;
  pointer-events: none;
  z-index: 0;
  background:
    linear-gradient(90deg, rgba(0,0,0,.94) 0%, rgba(0,0,0,.18) 48%, rgba(0,0,0,.94) 100%),
    radial-gradient(circle at 50% 55%, rgba(229,9,20,.26), rgba(0,0,0,0) 42%),
    url('/web/bacsflix-brand/bacsflix-logo-wallpaper.png?v=20260603v32') center 58% / min(82vw, 1220px) auto no-repeat,
    #040405;
  opacity: .94;
}

body.bacsflix-login-active #bacsflix-login-bg { display: block; }

body.bacsflix-login-active .backgroundContainer,
body.bacsflix-login-active .backdropContainer,
body.bacsflix-login-active .backgroundContainer.withBackdrop {
  background: transparent !important;
  opacity: 1 !important;
}

body.bacsflix-login-active .mainAnimatedPages,
body.bacsflix-login-active .page,
body.bacsflix-login-active .skinHeader,
body.bacsflix-login-active form,
body.bacsflix-login-active .manualLoginForm,
body.bacsflix-login-active .padded-left,
body.bacsflix-login-active .padded-right {
  position: relative;
  z-index: 2;
}

/* Login title/logo overlap fix: the wallpaper and mark already carry the brand. */
body.bacsflix-login-active .bacsflix-hide-login-title,
body.bacsflix-login-active h1.pageTitle,
body.bacsflix-login-active .loginTitle,
body.bacsflix-login-active .loginPageTitle,
body.bacsflix-login-active .manualLoginForm h1,
body.bacsflix-login-active .readOnlyContent h1 {
  display: none !important;
  visibility: hidden !important;
  height: 0 !important;
  margin: 0 !important;
  padding: 0 !important;
  overflow: hidden !important;
}

body.bacsflix-login-active .manualLoginForm,
body.bacsflix-login-active .loginDisclaimer,
body.bacsflix-login-active .readOnlyContent form {
  border-radius: 20px !important;
  background: rgba(10, 8, 9, .68) !important;
  border: 1px solid rgba(255,255,255,.08) !important;
  box-shadow: 0 0 42px rgba(229,9,20,.17), 0 20px 70px rgba(0,0,0,.62) !important;
  backdrop-filter: blur(10px) saturate(115%);
}

#bacsflix-login-mark {
  /* v3: Login formunun üstüne binen orta küçük logo tamamen kaldırıldı.
     Büyük wallpaper zaten markayı taşıyor; çakışma olmaması için görünmez kalır. */
  display: none !important;
  visibility: hidden !important;
  opacity: 0 !important;
  pointer-events: none !important;
}

body.bacsflix-login-active #bacsflix-login-mark { display: none !important; }

/* Top left brand: use the actual Bacsflix wordmark instead of the tiny Jellyfin-style mark. */
#bacsflix-topbrand {
  position: fixed;
  left: 14px;
  top: 8px;
  z-index: 10000;
  display: flex;
  align-items: center;
  justify-content: center;
  height: 54px;
  width: 248px;
  padding: 5px 18px;
  border-radius: 999px;
  background:
    radial-gradient(circle at 20% 50%, rgba(229,9,20,.20), rgba(0,0,0,0) 50%),
    linear-gradient(90deg, rgba(0,0,0,.88), rgba(58,0,5,.68), rgba(0,0,0,.82));
  border: 1px solid rgba(255,31,43,.42);
  box-shadow: 0 14px 34px rgba(0,0,0,.42), 0 0 34px rgba(229,9,20,.22), inset 0 0 0 1px rgba(255,255,255,.035);
  backdrop-filter: blur(12px);
  pointer-events: none;
  overflow: hidden;
}

#bacsflix-topbrand img {
  width: 218px !important;
  max-width: 218px !important;
  height: auto !important;
  max-height: 47px !important;
  object-fit: contain !important;
  object-position: center !important;
  filter: drop-shadow(0 0 16px rgba(229,9,20,.50));
  transform: translateY(-1px) !important;
}

/* v3.2: After login the wordmark/pill still sat a touch low in the Jellyfin header.
   Move only the app-shell brand upward; leave the login screen untouched. */
body.bacsflix-branded:not(.bacsflix-login-active) #bacsflix-topbrand img {
  transform: translateY(-7px) !important;
}
body.bacsflix-branded:not(.bacsflix-login-active) #bacsflix-topbrand {
  top: 0px !important;
}

#bacsflix-topbrand span { display: none !important; }
body.bacsflix-login-active #bacsflix-topbrand {
  top: 15px;
  width: 238px;
  height: 52px;
  opacity: .98;
}
body.bacsflix-login-active #bacsflix-topbrand img {
  width: 208px !important;
  max-width: 208px !important;
  max-height: 45px !important;
}

#bacsflix-footer-pill {
  display: none;
  position: fixed;
  left: 50%;
  bottom: 20px;
  transform: translateX(-50%);
  z-index: 10000;
  padding: 7px 14px;
  border-radius: 999px;
  background: rgba(0,0,0,.55);
  border: 1px solid rgba(229,9,20,.24);
  color: rgba(255,255,255,.90);
  font-size: 12px;
  letter-spacing: .02em;
  box-shadow: 0 0 24px rgba(229,9,20,.18);
  backdrop-filter: blur(10px);
  pointer-events: none;
}
body.bacsflix-login-active #bacsflix-footer-pill { display: block; }

/* Red login + app controls */
body.bacsflix-branded button.raised,
body.bacsflix-branded .emby-button.raised,
body.bacsflix-branded .button-submit,
body.bacsflix-branded .submit,
body.bacsflix-branded .paper-icon-button-light:hover,
body.bacsflix-branded .fab,
body.bacsflix-branded .button-flat:hover {
  background: linear-gradient(90deg, #b90008, #ff1b24) !important;
  color: #fff !important;
  border-radius: 10px !important;
  box-shadow: 0 0 18px rgba(229,9,20,.28) !important;
}

body.bacsflix-branded .emby-input:focus,
body.bacsflix-branded .emby-textarea:focus,
body.bacsflix-branded .emby-select-withcolor:focus,
body.bacsflix-branded .emby-checkbox:checked + span + .checkboxOutline,
body.bacsflix-branded .emby-checkbox:checked + .checkboxOutline {
  border-color: var(--bacsflix-red-hot) !important;
  box-shadow: 0 0 0 1px rgba(229,9,20,.33), 0 0 16px rgba(229,9,20,.20) !important;
}

/* Red app chrome after login */
body.bacsflix-branded:not(.bacsflix-login-active) .skinHeader,
body.bacsflix-branded:not(.bacsflix-login-active) .mainDrawer,
body.bacsflix-branded:not(.bacsflix-login-active) .navMenuOption-selected {
  background: linear-gradient(90deg, rgba(8,8,8,.98), rgba(32,0,3,.95), rgba(8,8,8,.98)) !important;
  border-bottom: 1px solid rgba(229,9,20,.23) !important;
  box-shadow: 0 10px 34px rgba(0,0,0,.30), inset 0 -1px rgba(229,9,20,.12) !important;
}

body.bacsflix-branded:not(.bacsflix-login-active) .mainAnimatedPages,
body.bacsflix-branded:not(.bacsflix-login-active) .page,
body.bacsflix-branded:not(.bacsflix-login-active) .libraryPage,
body.bacsflix-branded:not(.bacsflix-login-active) .homePage {
  background:
    radial-gradient(circle at 20% 0%, rgba(229,9,20,.10), rgba(0,0,0,0) 36%),
    radial-gradient(circle at 86% 10%, rgba(90,0,7,.16), rgba(0,0,0,0) 34%),
    linear-gradient(180deg, #0b0809 0%, #070707 45%, #040404 100%) !important;
}

body.bacsflix-branded .emby-tab-button-active,
body.bacsflix-branded .emby-tab-button:hover,
body.bacsflix-branded .navMenuOption:hover,
body.bacsflix-branded .listItem:hover {
  color: #fff !important;
  text-shadow: 0 0 12px rgba(229,9,20,.42) !important;
}

body.bacsflix-branded .emby-tab-button-active::after,
body.bacsflix-branded .emby-tabs-slider,
body.bacsflix-branded .sliderBubble,
body.bacsflix-branded .mdl-slider-background-lower,
body.bacsflix-branded .itemProgressBarForeground,
body.bacsflix-branded .playedIndicator,
body.bacsflix-branded .countIndicator,
body.bacsflix-branded .buttonAccent,
body.bacsflix-branded .accentButton,
body.bacsflix-branded .navMenuOption-selected {
  background: linear-gradient(90deg, #b90008, #ff1b24) !important;
  border-color: #ff1b24 !important;
}

body.bacsflix-branded .cardBox,
body.bacsflix-branded .visualCardBox,
body.bacsflix-branded .cardImageContainer,
body.bacsflix-branded .itemDetailPage .detailImageContainer,
body.bacsflix-branded .paperList,
body.bacsflix-branded .dialog {
  background-color: var(--bacsflix-card) !important;
}

body.bacsflix-branded .cardBox:hover,
body.bacsflix-branded .visualCardBox:hover,
body.bacsflix-branded .card:hover .cardBox,
body.bacsflix-branded .card:hover .visualCardBox {
  box-shadow: 0 0 0 1px rgba(229,9,20,.42), 0 18px 42px rgba(229,9,20,.14) !important;
}

body.bacsflix-branded .defaultCardBackground,
body.bacsflix-branded .defaultCardBackground1,
body.bacsflix-branded .defaultCardBackground2,
body.bacsflix-branded .defaultCardBackground3,
body.bacsflix-branded .defaultCardBackground4,
body.bacsflix-branded .defaultCardBackground5,
body.bacsflix-branded .cardImageContainer.defaultCardBackground,
body.bacsflix-branded .cardImageContainer.defaultCardBackground1,
body.bacsflix-branded .cardImageContainer.defaultCardBackground2,
body.bacsflix-branded .cardImageContainer.defaultCardBackground3,
body.bacsflix-branded .cardImageContainer.defaultCardBackground4,
body.bacsflix-branded .cardImageContainer.defaultCardBackground5 {
  background: radial-gradient(circle at 50% 18%, rgba(255,60,70,.48), rgba(130,0,8,.70) 48%, #250002 100%) !important;
}

body.bacsflix-branded .cardImageIcon,
body.bacsflix-branded .material-icons,
body.bacsflix-branded .md-icon {
  color: rgba(255,255,255,.90) !important;
}

body.bacsflix-branded a,
body.bacsflix-branded .textActionButton,
body.bacsflix-branded .button-link,
body.bacsflix-branded .fieldDescription a {
  color: #ff5b64 !important;
}

/* Hide common default Jellyfin brand marks; JS adds Bacsflix back on top. */
body.bacsflix-branded .pageTitleWithDefaultLogo,
body.bacsflix-branded .headerLogo,
body.bacsflix-branded .adminDrawerLogo,
body.bacsflix-branded img[alt='Jellyfin'],
body.bacsflix-branded img[title='Jellyfin'] {
  opacity: 0 !important;
  width: 0 !important;
  min-width: 0 !important;
  margin: 0 !important;
  padding: 0 !important;
}

@media (max-width: 760px) {
  #bacsflix-login-bg {
    background-size: 108vw auto;
    background-position: center 48%;
    opacity: .66;
  }
  #bacsflix-login-mark { display: none !important; }
  #bacsflix-topbrand {
    width: 176px;
    height: 44px;
    padding: 4px 12px;
  }
  #bacsflix-topbrand img {
    width: 152px !important;
    max-width: 152px !important;
    height: auto !important;
    max-height: 38px !important;
    object-fit: contain;
    object-position: center;
  }
}
CSS

  cat > "$WORK_DIR/bacsflix-brand.js" <<'JS'
/* Homelab v3.2 Bacsflix private Jellyfin branding overlay. */
(() => {
  const BRAND = 'Bacsflix';
  const TAGLINE = 'Stream your world.';
  const BASE = '/web/bacsflix-brand';
  const V = '20260603v32';
  const ICON = `${BASE}/bacsflix-icon.png?v=${V}`;
  const LOGO = `${BASE}/bacsflix-logo-transparent.png?v=${V}`;
  const WORDMARK = `${BASE}/bacsflix-wordmark-tight.png?v=${V}`;

  const SKIP_TAGS = new Set(['SCRIPT', 'STYLE', 'TEXTAREA', 'INPUT', 'CODE', 'PRE']);

  function isLoginPage() {
    const hash = (location.hash || '').toLowerCase();
    const path = (location.pathname || '').toLowerCase();
    if (hash.includes('login') || path.includes('login')) return true;
    const hasPassword = !!document.querySelector('input[type="password"]');
    const hasLogout = !!document.querySelector('[data-action="logout"], .btnLogout, [title*="Logout"], [title*="Çıkış"], [title*="Sign out"]');
    return hasPassword && !hasLogout;
  }

  function setTitle() {
    const t = document.title || '';
    if (/jellyfin/i.test(t)) {
      document.title = t.replace(/jellyfin/ig, BRAND);
    } else if (!/bacsflix/i.test(t)) {
      document.title = t ? `${t} - ${BRAND}` : BRAND;
    }
  }

  function setFavicons() {
    document.querySelectorAll('link[rel~="icon"], link[rel="shortcut icon"], link[rel="apple-touch-icon"]').forEach((el) => {
      if (!String(el.href || '').includes('/bacsflix-brand/')) el.parentNode && el.parentNode.removeChild(el);
    });
    const head = document.head || document.documentElement;
    if (!document.querySelector('link[data-bacsflix-favicon="1"]')) {
      const icon = document.createElement('link');
      icon.rel = 'icon';
      icon.type = 'image/png';
      icon.href = ICON;
      icon.dataset.bacsflixFavicon = '1';
      head.appendChild(icon);
      const apple = document.createElement('link');
      apple.rel = 'apple-touch-icon';
      apple.href = ICON;
      apple.dataset.bacsflixFavicon = '1';
      head.appendChild(apple);
    }
  }

  function replaceAttributes() {
    document.querySelectorAll('[alt], [title], [aria-label]').forEach((el) => {
      ['alt', 'title', 'aria-label'].forEach((attr) => {
        const v = el.getAttribute(attr);
        if (v && /jellyfin/i.test(v)) el.setAttribute(attr, v.replace(/jellyfin/ig, BRAND));
      });
    });
  }

  function replaceTextNodes(root = document.body) {
    if (!root) return;
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        if (!node.nodeValue || !/jellyfin/i.test(node.nodeValue)) return NodeFilter.FILTER_REJECT;
        const p = node.parentElement;
        if (!p || SKIP_TAGS.has(p.tagName)) return NodeFilter.FILTER_REJECT;
        if (p.closest('#bacsflix-topbrand, #bacsflix-footer-pill, script, style, textarea, input, code, pre')) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    nodes.forEach((n) => { n.nodeValue = n.nodeValue.replace(/jellyfin/ig, BRAND); });
  }

  function ensureDiv(id, html) {
    let el = document.getElementById(id);
    if (!el) {
      el = document.createElement('div');
      el.id = id;
      if (html) el.innerHTML = html;
      document.body.appendChild(el);
    }
    return el;
  }

  function ensureOverlays() {
    if (!document.body) return;
    ensureDiv('bacsflix-login-bg', '');
    ensureDiv('bacsflix-login-mark', '');
    ensureDiv('bacsflix-footer-pill', `${BRAND} — ${TAGLINE}`);
    const top = ensureDiv('bacsflix-topbrand', `<img src="${WORDMARK}" alt="${BRAND}"><span>${BRAND}</span>`);
    const img = top.querySelector('img');
    if (img && (!String(img.src || '').includes(`v=${V}`) || !String(img.src || '').includes('bacsflix-wordmark-tight'))) img.src = WORDMARK;
  }

  function hideLoginTitle() {
    if (!isLoginPage()) return;
    const loginPhrases = /^(please sign in|sign in|log in|login|lütfen oturum açın|oturum aç|giriş yap)$/i;
    document.querySelectorAll('h1, h2, .pageTitle, .sectionTitle, .loginTitle, .loginPageTitle').forEach((el) => {
      const text = (el.textContent || '').trim();
      if (loginPhrases.test(text)) el.classList.add('bacsflix-hide-login-title');
    });
  }

  function hideDefaultBrandImages() {
    document.querySelectorAll('img, picture, svg').forEach((el) => {
      const label = `${el.getAttribute('alt') || ''} ${el.getAttribute('title') || ''} ${el.getAttribute('class') || ''} ${el.getAttribute('src') || ''}`;
      if (/jellyfin/i.test(label) && !/bacsflix/i.test(label)) {
        el.style.opacity = '0';
        el.style.width = '0px';
        el.style.minWidth = '0px';
        el.style.margin = '0px';
      }
    });
  }

  function applyBranding() {
    if (!document.documentElement || !document.body) return;
    document.body.classList.add('bacsflix-branded');
    document.body.classList.toggle('bacsflix-login-active', isLoginPage());
    setTitle();
    setFavicons();
    ensureOverlays();
    hideLoginTitle();
    replaceAttributes();
    replaceTextNodes();
    hideDefaultBrandImages();
  }

  let queued = false;
  function schedule() {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => {
      queued = false;
      applyBranding();
    });
  }

  window.addEventListener('hashchange', schedule, true);
  window.addEventListener('popstate', schedule, true);
  window.addEventListener('load', schedule, true);

  const start = () => {
    applyBranding();
    new MutationObserver(schedule).observe(document.documentElement, {
      childList: true,
      subtree: true,
      characterData: true,
      attributes: true,
      attributeFilter: ['alt', 'title', 'aria-label', 'class']
    });
    setInterval(applyBranding, 2500);
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start, { once: true });
  } else {
    start();
  }
})();
JS
}

patch_index() {
  local index_file="$1"
  python3 - "$index_file" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
html = p.read_text(encoding='utf-8', errors='ignore')
start = '<!-- bacsflix-brand-loader-start -->'
end = '<!-- bacsflix-brand-loader-end -->'
block = """<!-- bacsflix-brand-loader-start -->
<link rel=\"stylesheet\" href=\"/web/bacsflix-brand/bacsflix-brand.css?v=20260603v32\">
<script defer src=\"/web/bacsflix-brand/bacsflix-brand.js?v=20260603v32\"></script>
<!-- bacsflix-brand-loader-end -->
"""
if start in html and end in html:
    before = html.split(start, 1)[0]
    after = html.split(end, 1)[1]
    html = before + block + after
elif '</head>' in html:
    html = html.replace('</head>', block + '</head>', 1)
else:
    html = block + html
p.write_text(html, encoding='utf-8')
PY
}

apply_brand() {
  log "Container: $CONTAINER"
  log "Web root : $WEBROOT"

  local backup_dir="$BACKUP_ROOT/$STAMP"
  mkdir -p "$backup_dir"

  log "Yedek alınıyor: $backup_dir"
  docker cp "$CONTAINER:$WEBROOT/index.html" "$backup_dir/index.html"
  if docker exec "$CONTAINER" sh -lc "test -d '$WEBROOT/bacsflix-brand'" >/dev/null 2>&1; then
    docker cp "$CONTAINER:$WEBROOT/bacsflix-brand" "$backup_dir/bacsflix-brand.previous" >/dev/null 2>&1 || true
  fi

  write_brand_files

  log "Bacsflix v3.2 assetleri container içine kopyalanıyor"
  docker exec "$CONTAINER" sh -lc "mkdir -p '$WEBROOT/bacsflix-brand'"
  docker cp "$ASSET_DIR/bacsflix-logo-wallpaper.png" "$CONTAINER:$WEBROOT/bacsflix-brand/bacsflix-logo-wallpaper.png"
  docker cp "$ASSET_DIR/bacsflix-logo-transparent.png" "$CONTAINER:$WEBROOT/bacsflix-brand/bacsflix-logo-transparent.png"
  docker cp "$ASSET_DIR/bacsflix-icon.png" "$CONTAINER:$WEBROOT/bacsflix-brand/bacsflix-icon.png"
  docker cp "$ASSET_DIR/bacsflix-wordmark-tight.png" "$CONTAINER:$WEBROOT/bacsflix-brand/bacsflix-wordmark-tight.png"
  docker cp "$ASSET_DIR/favicon.png" "$CONTAINER:$WEBROOT/bacsflix-brand/favicon.png"
  docker cp "$ASSET_DIR/bacmaster-logo.png" "$CONTAINER:$WEBROOT/bacsflix-brand/bacmaster-logo.png"
  docker cp "$WORK_DIR/bacsflix-brand.css" "$CONTAINER:$WEBROOT/bacsflix-brand/bacsflix-brand.css"
  docker cp "$WORK_DIR/bacsflix-brand.js" "$CONTAINER:$WEBROOT/bacsflix-brand/bacsflix-brand.js"

  log "index.html içine güvenli loader enjekte ediliyor"
  docker cp "$CONTAINER:$WEBROOT/index.html" "$WORK_DIR/index.html"
  patch_index "$WORK_DIR/index.html"
  docker cp "$WORK_DIR/index.html" "$CONTAINER:$WEBROOT/index.html"

  log "Jellyfin container yeniden başlatılıyor"
  docker restart "$CONTAINER" >/dev/null

  status
  echo "✅ Bacsflix branding uygulandı. URL: http://192.168.50.106:8096/web/"
  echo "ℹ️  Tarayıcı cache'i için Ctrl+F5 veya gizli sekme önerilir."
}

restore_brand() {
  log "Container: $CONTAINER"
  log "Web root : $WEBROOT"
  local latest
  latest="$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -n1 || true)"
  [[ -n "$latest" && -f "$latest/index.html" ]] || fail "Geri yüklenebilir yedek bulunamadı: $BACKUP_ROOT"
  log "Geri yükleniyor: $latest/index.html"
  docker cp "$latest/index.html" "$CONTAINER:$WEBROOT/index.html"
  docker exec "$CONTAINER" sh -lc "rm -rf '$WEBROOT/bacsflix-brand'" || true
  docker restart "$CONTAINER" >/dev/null
  status
  echo "✅ Restore tamamlandı."
}

case "$MODE" in
  apply) apply_brand ;;
  restore) restore_brand ;;
  status) status ;;
esac
