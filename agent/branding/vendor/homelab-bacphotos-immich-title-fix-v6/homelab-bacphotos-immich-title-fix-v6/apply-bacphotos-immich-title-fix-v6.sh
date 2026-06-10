#!/usr/bin/env bash
set -Eeuo pipefail
set +H

# Homelab - Immich BacPhotos Title Fix v6
# Runs on Proxmox root, connects to VM106, and patches Immich server/web runtime title strings.
# This is intentionally deeper than v5: it patches compiled JS/MJS/CJS/JSON/HTML plus pre-compressed .gz/.br assets.
# Modes: apply | restore | status | discover

MODE="${1:-apply}"
VM106_IP="${VM106_IP:-192.168.50.106}"
IMMICH_HTTP_URL="${IMMICH_HTTP_URL:-http://127.0.0.1:2283}"
USERS_ENV="${USERS_ENV:-/root/homelab-secrets/users.env}"
SSH_USER="${SSH_USER:-}"
SSH_PASS="${SSH_PASS:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSET_DIR="${BACP_ASSET_DIR:-$SCRIPT_DIR/assets/bacphotos}"

case "$MODE" in
  apply|restore|status|discover) ;;
  *) echo "Usage: $0 [apply|restore|status|discover]" >&2; exit 2 ;;
esac

echo
echo "Homelab - Immich BacPhotos Title Fix v6"
echo "Mode: $MODE"
echo "Target VM: $VM106_IP"
echo

if [[ -f "$USERS_ENV" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$USERS_ENV"
  set +a
fi

SSH_USER="${SSH_USER:-${BACMASTER_USER:-bacmaster}}"
SSH_PASS="${SSH_PASS:-${BACMASTER_PASS:-}}"

for f in \
  "$ASSET_DIR/bacphotos-icon-32.png" \
  "$ASSET_DIR/bacphotos-icon-180.png" \
  "$ASSET_DIR/bacphotos-icon-192.png" \
  "$ASSET_DIR/bacphotos-icon-512.png" \
  "$ASSET_DIR/favicon.ico" \
  "$ASSET_DIR/bacphotos-favicon.svg"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: Missing asset: $f" >&2
    exit 1
  fi
done

if [[ -n "$SSH_PASS" ]]; then
  if ! command -v sshpass >/dev/null 2>&1; then
    echo "Installing sshpass on Proxmox..."
    apt update >/dev/null
    apt install -y sshpass >/dev/null
  fi
fi

for cmd in base64 scp ssh tar; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Installing required packages on Proxmox..."
    apt update >/dev/null
    apt install -y openssh-client coreutils tar >/dev/null
    break
  fi
done

b64() { printf '%s' "$1" | base64 -w0; }
MODE_B64="$(b64 "$MODE")"
IMMICH_HTTP_URL_B64="$(b64 "$IMMICH_HTTP_URL")"

TMP_LOCAL="$(mktemp)"
cat > "$TMP_LOCAL" <<'REMOTE_BODY'
#!/usr/bin/env bash
set -Eeuo pipefail
set +H

MODE="$(printf '%s' "${MODE_B64:?}" | base64 -d)"
IMMICH_HTTP_URL="$(printf '%s' "${IMMICH_HTTP_URL_B64:?}" | base64 -d)"
ASSET_SOURCE="${ASSET_SOURCE:?}"
IMMICH_DIR="/opt/homelab/immich"
BRANDING_DIR="$IMMICH_DIR/branding/bacphotos"
ASSET_DIR="$BRANDING_DIR/assets-title-fix-v6"
BACKUP_DIR="$BRANDING_DIR/backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$BRANDING_DIR/runtime-title-fix-v6-$STAMP"
MAP_FILE="$BACKUP_DIR/title-fix-v6-$STAMP.tsv"
LATEST_MAP="$BACKUP_DIR/title-fix-v6-latest.tsv"
DISCOVERY_FILE="$BACKUP_DIR/title-fix-v6-discovery-$STAMP.txt"

mkdir -p "$ASSET_DIR" "$BACKUP_DIR" "$RUN_DIR"
chmod 700 "$BRANDING_DIR" "$BACKUP_DIR" "$RUN_DIR" 2>/dev/null || true
cp -f "$ASSET_SOURCE"/* "$ASSET_DIR"/

need_cmds() {
  local missing=0
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || missing=1; done
  if [[ "$missing" == "1" ]]; then
    apt update >/dev/null
    apt install -y python3 curl coreutils findutils tar gzip brotli >/dev/null
  fi
}
need_cmds python3 curl base64 find sed grep tar awk stat gzip brotli

ICON_32="$ASSET_DIR/bacphotos-icon-32.png"
ICON_180="$ASSET_DIR/bacphotos-icon-180.png"
ICON_192="$ASSET_DIR/bacphotos-icon-192.png"
ICON_512="$ASSET_DIR/bacphotos-icon-512.png"
FAVICON_ICO="$ASSET_DIR/favicon.ico"
FAVICON_SVG="$ASSET_DIR/bacphotos-favicon.svg"

for f in "$ICON_32" "$ICON_180" "$ICON_192" "$ICON_512" "$FAVICON_ICO" "$FAVICON_SVG"; do
  [[ -f "$f" ]] || { echo "ERROR: Missing remote asset $f" >&2; exit 1; }
done

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker command not found on VM106." >&2
  exit 1
fi

find_immich_containers() {
  docker ps --format '{{.Names}}' \
    | grep -Ei '(^|[-_])immich|immich($|[-_])|hb-immich' \
    | awk '
      /server|web|frontend/ { print "0\t" $0; next }
      /machine|learning|postgres|redis|database|db/ { print "2\t" $0; next }
      { print "1\t" $0 }
    ' \
    | sort -u \
    | cut -f2- || true
}

is_non_web_container() {
  local lower
  lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *postgres*|*database*|*redis*|*machine*|*learning*) return 0 ;;
    *) return 1 ;;
  esac
}

container_cp_from() { docker cp "$1:$2" "$3" >/dev/null 2>&1; }
container_cp_to() { docker cp "$1" "$2:$3" >/dev/null 2>&1; }

ensure_container_tar_list() {
  local c="$1" out="$RUN_DIR/tarlist-$c.txt"
  if [[ ! -f "$out" ]]; then
    echo "==> Export-scanning container filesystem: $c" >&2
    if ! docker export "$c" 2>/dev/null | tar -tf - > "$out" 2>/dev/null; then
      : > "$out"
    fi
  fi
  printf '%s' "$out"
}

norm_path() {
  local p="$1"
  p="${p#./}"
  p="${p#/}"
  printf '/%s' "$p"
}

backup_from_container() {
  local c="$1" path="$2" kind="$3" out safe base
  safe="$(printf '%s' "$path" | sed 's#/#__#g')"
  base="$BACKUP_DIR/title-fix-v6/$STAMP/$c/$kind"
  mkdir -p "$base"
  out="$base/$safe"
  if docker cp "$c:$path" "$out" >/dev/null 2>&1; then
    printf '%s\t%s\t%s\t%s\n' "$c" "$path" "$out" "$kind" >> "$MAP_FILE"
    return 0
  fi
  return 1
}

record_new_file() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "__NEW__" "$3" >> "$MAP_FILE"; }

container_path_exists() {
  local c="$1" path="$2" tmp="$RUN_DIR/probe-$(date +%s%N)"
  if docker cp "$c:$path" "$tmp" >/dev/null 2>&1; then
    rm -rf "$tmp" >/dev/null 2>&1 || true
    return 0
  fi
  rm -rf "$tmp" >/dev/null 2>&1 || true
  return 1
}

copy_asset_to_path() {
  local c="$1" dest="$2" src="$3" kind="${4:-asset}"
  if container_path_exists "$c" "$dest"; then backup_from_container "$c" "$dest" "$kind" >/dev/null || true; else record_new_file "$c" "$dest" "$kind"; fi
  docker cp "$src" "$c:$dest" >/dev/null 2>&1
}

make_title_hook_js() {
  local output="$1"
  cat > "$output" <<'JS'
(function () {
  var BRAND = "BacPhotos";
  var BRAND_RE = /Immich/g;
  var ICON = "/bacphotos-favicon-32.png";
  function rewriteTitle() {
    try {
      var t = document.title || "";
      var n = t.replace(BRAND_RE, BRAND);
      if (!n || n.trim() === "" || n.trim().toLowerCase() === "immich") n = BRAND;
      if (document.title !== n) document.title = n;
    } catch (e) {}
  }
  function upsertIcon(id, rel, href, sizes, type) {
    try {
      var el = document.getElementById(id);
      if (!el) { el = document.createElement("link"); el.id = id; document.head.appendChild(el); }
      el.setAttribute("rel", rel);
      el.setAttribute("href", href + "?v=" + Date.now());
      if (sizes) el.setAttribute("sizes", sizes);
      if (type) el.setAttribute("type", type);
    } catch (e) {}
  }
  function rewriteIcons() {
    try {
      Array.prototype.slice.call(document.querySelectorAll("link[rel]")).forEach(function (link) {
        var rel = (link.getAttribute("rel") || "").toLowerCase();
        if ((rel.indexOf("icon") !== -1 || rel.indexOf("apple-touch-icon") !== -1 || rel.indexOf("mask-icon") !== -1) &&
            (link.id || "").indexOf("homelab-bacphotos") !== 0) {
          if (link.parentNode) link.parentNode.removeChild(link);
        }
      });
      upsertIcon("homelab-bacphotos-favicon-live", "icon", ICON, "32x32", "image/png");
      upsertIcon("homelab-bacphotos-shortcut-live", "shortcut icon", "/favicon.ico", "32x32", "image/x-icon");
      upsertIcon("homelab-bacphotos-apple-live", "apple-touch-icon", "/apple-touch-icon.png", "180x180", "image/png");
    } catch (e) {}
  }
  function run() { rewriteTitle(); rewriteIcons(); }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", run); else run();
  try {
    var title = document.querySelector("title") || document.head.appendChild(document.createElement("title"));
    new MutationObserver(rewriteTitle).observe(title, { childList: true, characterData: true, subtree: true });
    new MutationObserver(run).observe(document.head, { childList: true, subtree: true });
  } catch (e) {}
  try {
    var d = Object.getOwnPropertyDescriptor(Document.prototype, "title") || Object.getOwnPropertyDescriptor(HTMLDocument.prototype, "title");
    if (d && d.configurable) {
      Object.defineProperty(document, "title", {
        configurable: true,
        get: function () { return d.get.call(document); },
        set: function (value) { return d.set.call(document, String(value || "").replace(BRAND_RE, BRAND)); }
      });
    }
  } catch (e) {}
  var rawPush = history.pushState, rawReplace = history.replaceState;
  history.pushState = function () { var r = rawPush.apply(this, arguments); setTimeout(run, 0); return r; };
  history.replaceState = function () { var r = rawReplace.apply(this, arguments); setTimeout(run, 0); return r; };
  window.addEventListener("popstate", run);
  window.addEventListener("hashchange", run);
  setInterval(run, 100);
})();
JS
}

make_manifest() {
  local output="$1"
  cat > "$output" <<JSON
{
  "name": "BacPhotos",
  "short_name": "BacPhotos",
  "description": "BacPhotos - Your memories. Your way.",
  "start_url": "/",
  "scope": "/",
  "display": "standalone",
  "background_color": "#050509",
  "theme_color": "#050509",
  "icons": [
    { "src": "/bacphotos-favicon-32.png", "sizes": "32x32", "type": "image/png" },
    { "src": "/apple-touch-icon.png", "sizes": "180x180", "type": "image/png" },
    { "src": "/bacphotos-icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/bacphotos-icon-512.png", "sizes": "512x512", "type": "image/png" }
  ]
}
JSON
}

patch_plain_text_file() {
  local in="$1" out="$2" fname="$3" stamp="$4"
  python3 - "$in" "$out" "$fname" "$stamp" <<'PY'
import json, pathlib, re, sys
inp, outp, fname, stamp = sys.argv[1:]
raw = pathlib.Path(inp).read_bytes()
try:
    text = raw.decode('utf-8')
except UnicodeDecodeError:
    text = raw.decode('utf-8', errors='ignore')
old = text
# Remove older hooks, then replace brand display strings.
text = re.sub(r"\n?<!-- BEGIN HOMELAB BACPHOTOS TAB BRANDING.*?<!-- END HOMELAB BACPHOTOS TAB BRANDING.*?-->\n?", "\n", text, flags=re.S)
for a,b in [
    (" - Immich", " - BacPhotos"), (" — Immich", " — BacPhotos"), (" | Immich", " | BacPhotos"),
    ("Login - Immich", "Login - BacPhotos"), ("Trash - Immich", "Trash - BacPhotos"), ("Çöp - Immich", "Çöp - BacPhotos"),
    (">Immich<", ">BacPhotos<"), ('"Immich"', '"BacPhotos"'), ("'Immich'", "'BacPhotos'"), ("`Immich`", "`BacPhotos`"),
    ("Immich", "BacPhotos"),
]:
    text = text.replace(a,b)

lower = fname.lower()
if lower.endswith(('.json','.webmanifest')) or lower.startswith('manifest'):
    try:
        data = json.loads(text)
        if isinstance(data, dict):
            data['name'] = 'BacPhotos'
            data['short_name'] = 'BacPhotos'
            data['description'] = 'BacPhotos - Your memories. Your way.'
            text = json.dumps(data, ensure_ascii=False, indent=2)
    except Exception:
        pass

if lower.endswith('.html') or lower == 'index.html':
    if re.search(r"<title>.*?</title>", text, flags=re.I|re.S):
        text = re.sub(r"<title>.*?</title>", "<title>BacPhotos</title>", text, count=1, flags=re.I|re.S)
    else:
        text = re.sub(r"</head>", "<title>BacPhotos</title>\n</head>", text, count=1, flags=re.I)
    text = re.sub(r"\s*<link\b[^>]*\brel=[\"'][^\"']*(?:shortcut\s+icon|apple-touch-icon|mask-icon|icon)[^\"']*[\"'][^>]*>\s*", "\n", text, flags=re.I)
    block = f'''
<!-- BEGIN HOMELAB BACPHOTOS TAB BRANDING V6 -->
<link id="homelab-bacphotos-favicon" rel="icon" type="image/png" sizes="32x32" href="/bacphotos-favicon-32.png?v={stamp}">
<link id="homelab-bacphotos-shortcut-icon" rel="shortcut icon" type="image/x-icon" href="/favicon.ico?v={stamp}">
<link id="homelab-bacphotos-apple-touch-icon" rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png?v={stamp}">
<link id="homelab-bacphotos-manifest" rel="manifest" href="/manifest.webmanifest?v={stamp}">
<meta name="application-name" content="BacPhotos">
<meta name="apple-mobile-web-app-title" content="BacPhotos">
<script defer src="/homelab-bacphotos-title-fix.js?v={stamp}"></script>
<!-- END HOMELAB BACPHOTOS TAB BRANDING V6 -->
'''
    if re.search(r"</head>", text, flags=re.I):
        text = re.sub(r"</head>", block + "</head>", text, count=1, flags=re.I)
    else:
        text += block
pathlib.Path(outp).write_text(text, encoding='utf-8')
PY
}

should_consider_path() {
  local p="$1" l
  l="$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')"
  case "$l" in
    */node_modules/*|*/uploads/*|*/upload/*|*/cache/*|*/.cache/*|*/tmp/*|*/log/*|*/logs/*|*/postgres*|*/redis*) return 1 ;;
  esac
  case "$l" in
    */usr/src/app/*|*/app/*|*/usr/share/nginx/html/*|*/opt/immich/*) ;;
    *) return 1 ;;
  esac
  case "$l" in
    *.html|*.js|*.mjs|*.cjs|*.json|*.webmanifest|*/manifest*|*.html.gz|*.js.gz|*.mjs.gz|*.cjs.gz|*.json.gz|*.webmanifest.gz|*.html.br|*.js.br|*.mjs.br|*.cjs.br|*.json.br|*.webmanifest.br) return 0 ;;
    *) return 1 ;;
  esac
}

is_index_like_path() {
  local b="$(basename "$1" | tr '[:upper:]' '[:lower:]')"
  case "$b" in index.html|manifest*|*.webmanifest) return 0 ;; *) return 1 ;; esac
}

patch_container_file() {
  local c="$1" path="$2" base lower size src work decoded patched encoded mode changed=0
  base="$(basename "$path")"
  lower="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
  src="$RUN_DIR/file-$(printf '%s' "$c-$path" | sed 's#[/: ]#_#g').orig"
  work="$RUN_DIR/file-$(printf '%s' "$c-$path" | sed 's#[/: ]#_#g')"
  decoded="$work.decoded"
  patched="$work.patched"
  encoded="$work.encoded"

  docker cp "$c:$path" "$src" >/dev/null 2>&1 || return 0
  size="$(stat -c%s "$src" 2>/dev/null || echo 999999999)"
  [[ "$size" -gt 50000000 ]] && return 0

  mode="plain"
  case "$lower" in
    *.gz) mode="gz"; gzip -dc "$src" > "$decoded" 2>/dev/null || return 0 ;;
    *.br) mode="br"; brotli -dc "$src" > "$decoded" 2>/dev/null || return 0 ;;
    *) cp -f "$src" "$decoded" ;;
  esac

  # Patch index/manifest always; other runtime files only if decompressed content includes Immich.
  if ! is_index_like_path "$path" && ! grep -a -q 'Immich' "$decoded" 2>/dev/null; then
    return 0
  fi

  patch_plain_text_file "$decoded" "$patched" "$base" "$STAMP"
  if cmp -s "$decoded" "$patched"; then
    return 0
  fi

  case "$mode" in
    gz) gzip -n -9 -c "$patched" > "$encoded" ;;
    br) brotli -f -q 11 -c "$patched" > "$encoded" ;;
    plain) cp -f "$patched" "$encoded" ;;
  esac

  backup_from_container "$c" "$path" "runtime-title" >/dev/null || true
  if docker cp "$encoded" "$c:$path" >/dev/null 2>&1; then
    echo "OK: Patched title string asset: $c:$path"
    return 0
  fi
  return 0
}

find_index_roots() {
  local c="$1" tarlist
  tarlist="$(ensure_container_tar_list "$c")"
  grep -E '(^|/)index\.html$' "$tarlist" 2>/dev/null \
    | grep -E '(www|web|dist|build|browser|client|public|html|app)' \
    | while IFS= read -r p; do dirname "$(norm_path "$p")"; done \
    | sort -u || true
}

install_root_public_assets() {
  local c="$1" root="$2" manifest hook
  manifest="$RUN_DIR/manifest.webmanifest"
  hook="$RUN_DIR/homelab-bacphotos-title-fix.js"
  make_manifest "$manifest"
  make_title_hook_js "$hook"
  for pair in \
    "bacphotos-favicon-32.png:$ICON_32" \
    "bacphotos-icon-192.png:$ICON_192" \
    "bacphotos-icon-512.png:$ICON_512" \
    "apple-touch-icon.png:$ICON_180" \
    "favicon.ico:$FAVICON_ICO" \
    "favicon.png:$ICON_32" \
    "favicon.svg:$FAVICON_SVG" \
    "manifest.webmanifest:$manifest" \
    "site.webmanifest:$manifest" \
    "homelab-bacphotos-title-fix.js:$hook"; do
    local name="${pair%%:*}" src="${pair#*:}"
    copy_asset_to_path "$c" "$root/$name" "$src" "public-asset"
  done
}

replace_icon_assets() {
  local c="$1" tarlist="$2" p l src
  while IFS= read -r p; do
    p="$(norm_path "$p")"
    l="$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')"
    case "$l" in
      */node_modules/*|*/postgres*|*/redis*|*/machine*|*/learning*) continue ;;
    esac
    case "$l" in
      *favicon.ico) src="$FAVICON_ICO" ;;
      *favicon*.svg) src="$FAVICON_SVG" ;;
      *apple-touch-icon*.png|*180*.png) src="$ICON_180" ;;
      *192*.png|*android-chrome-192*.png) src="$ICON_192" ;;
      *512*.png|*android-chrome-512*.png) src="$ICON_512" ;;
      *favicon*.png|*icon*.png|*logo*.png) src="$ICON_32" ;;
      *) continue ;;
    esac
    if [[ -f "$src" ]] && docker cp "$src" "$c:$p" >/dev/null 2>&1; then
      backup_from_container "$c" "$p" "icon" >/dev/null || true
      echo "OK: Refreshed icon asset: $c:$p"
    fi
  done < <(grep -Ei '(^|/)(favicon[^/]*\.(ico|png|svg)|apple-touch-icon[^/]*\.png|android-chrome[^/]*\.png|icon[-_0-9a-z]*\.png|logo[-_0-9a-z]*\.png)$' "$tarlist" 2>/dev/null || true)
}

apply_patch() {
  : > "$MAP_FILE"
  : > "$RUN_DIR/patched-files.txt"
  local containers=0 web_containers=0 candidates=0
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    containers=$((containers + 1))
    echo "==> Immich container detected: $c"
    if is_non_web_container "$c"; then
      echo "INFO: Skipping support container: $c"
      continue
    fi
    web_containers=$((web_containers + 1))
    local tarlist root p
    tarlist="$(ensure_container_tar_list "$c")"

    # Ensure the live hook/favicon assets exist next to every discovered index.html.
    while IFS= read -r root; do
      [[ -n "$root" ]] || continue
      echo "==> Installing BacPhotos public hook/assets in: $c:$root"
      install_root_public_assets "$c" "$root"
    done < <(find_index_roots "$c")

    replace_icon_assets "$c" "$tarlist" || true

    # Patch compiled server/client runtime assets, including precompressed browser assets.
    while IFS= read -r p; do
      p="$(norm_path "$p")"
      should_consider_path "$p" || continue
      candidates=$((candidates + 1))
      patch_container_file "$c" "$p"
    done < "$tarlist"

    echo "==> Restarting Immich server/web container: $c"
    docker restart "$c" >/dev/null 2>&1 || true
  done < <(find_immich_containers)

  ln -sfn "$MAP_FILE" "$LATEST_MAP" 2>/dev/null || cp -f "$MAP_FILE" "$LATEST_MAP"
  sleep 8
  echo
  echo "Summary: containers=$containers web_containers=$web_containers candidate_assets=$candidates changed_entries=$(wc -l < "$MAP_FILE" | tr -d ' ')"
  echo "Backup map: $MAP_FILE"
  verify_live
  echo "OK: BacPhotos Immich title fix v6 applied."
}

verify_live() {
  echo
  echo "==> Live verification"
  local urls=("$IMMICH_HTTP_URL" "http://127.0.0.1:2283" "http://localhost:2283") u
  for u in "${urls[@]}"; do
    [[ -n "$u" ]] || continue
    if curl -fsSL --max-time 12 "$u/trash" -o "$RUN_DIR/live-trash.html" 2>/dev/null || curl -fsSL --max-time 12 "$u/" -o "$RUN_DIR/live-trash.html" 2>/dev/null; then
      if grep -a -q 'Immich' "$RUN_DIR/live-trash.html"; then
        echo "WARN: Live HTML still contains Immich string. Browser route JS may still have cached asset; close all tabs and hard reload."
      fi
      if grep -a -qE 'BacPhotos|homelab-bacphotos' "$RUN_DIR/live-trash.html"; then
        echo "OK: Live HTML contains BacPhotos marker: $u"
      else
        echo "INFO: Live HTML fetched, BacPhotos marker not visible in raw HTML. Runtime JS patch may still handle title."
      fi
      return 0
    fi
  done
  echo "WARN: Live HTTP verification could not fetch Immich."
}

restore_patch() {
  local map="$LATEST_MAP"
  if [[ ! -f "$map" ]]; then echo "WARN: No latest backup map found at $map"; return 0; fi
  tac "$map" | while IFS=$'\t' read -r c path backup kind; do
    [[ -n "${c:-}" && -n "${path:-}" ]] || continue
    docker ps --format '{{.Names}}' | grep -Fxq "$c" || continue
    if [[ "${backup:-}" == "__NEW__" ]]; then
      docker exec "$c" sh -c "rm -f '$path'" >/dev/null 2>&1 || true
      echo "OK: Removed/ignored new $kind: $c:$path"
    elif [[ -f "${backup:-}" ]]; then
      docker cp "$backup" "$c:$path" >/dev/null 2>&1 && echo "OK: Restored $kind: $c:$path"
    fi
  done
  find_immich_containers | while read -r c; do [[ -n "$c" ]] && ! is_non_web_container "$c" && docker restart "$c" >/dev/null 2>&1 || true; done
  echo "OK: Restore attempted from $map"
}

status_patch() {
  echo "==> Status"
  local c tarlist remain=0 roots=0
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    echo "Container: $c"
    if is_non_web_container "$c"; then echo "  Support container: skipped"; continue; fi
    tarlist="$(ensure_container_tar_list "$c")"
    while read -r root; do [[ -n "$root" ]] && roots=$((roots+1)) && echo "  Index root: $root"; done < <(find_index_roots "$c")
    # Sample remaining uncompressed Immich refs only. Compressed refs are checked by apply.
    while IFS= read -r p; do
      p="$(norm_path "$p")"
      should_consider_path "$p" || continue
      case "$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')" in *.gz|*.br) continue ;; esac
      local tmp="$RUN_DIR/status-$(printf '%s' "$c-$p" | sed 's#[/: ]#_#g')"
      docker cp "$c:$p" "$tmp" >/dev/null 2>&1 || continue
      if grep -a -q 'Immich' "$tmp" 2>/dev/null; then
        echo "  Remaining Immich string: $p"
        remain=$((remain+1))
        [[ "$remain" -gt 20 ]] && break
      fi
    done < "$tarlist"
  done < <(find_immich_containers)
  echo "STATUS: index_roots=$roots remaining_sample_count=$remain"
  [[ -f "$LATEST_MAP" ]] && echo "STATUS: Latest backup map: $LATEST_MAP ($(wc -l < "$LATEST_MAP" | tr -d ' ') entries)"
  verify_live
}

discover_paths() {
  : > "$DISCOVERY_FILE"
  local c tarlist
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    {
      echo "===== CONTAINER: $c ====="
      docker inspect -f 'image={{.Config.Image}} cmd={{json .Config.Cmd}}' "$c" 2>/dev/null || true
      echo "-- index roots --"
    } >> "$DISCOVERY_FILE"
    find_index_roots "$c" >> "$DISCOVERY_FILE" || true
    tarlist="$(ensure_container_tar_list "$c")"
    {
      echo "-- files with Immich in path candidates --"
      grep -Ei '(^|/)(index\.html|manifest[^/]*|.*\.(js|mjs|cjs|json|webmanifest)(\.gz|\.br)?)$' "$tarlist" 2>/dev/null | head -200
      echo
    } >> "$DISCOVERY_FILE"
  done < <(find_immich_containers)
  cat "$DISCOVERY_FILE"
}

case "$MODE" in
  apply) apply_patch ;;
  restore) restore_patch ;;
  status) status_patch ;;
  discover) discover_paths ;;
esac

rm -rf "$RUN_DIR" 2>/dev/null || true
REMOTE_BODY
chmod 600 "$TMP_LOCAL"

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10)
REMOTE_DIR="/tmp/immich-bacphotos-title-fix-v6-$$"
REMOTE_SCRIPT="$REMOTE_DIR/remote.sh"
REMOTE_ASSETS="$REMOTE_DIR/assets"

run_ssh() {
  local cmd="$1"
  if [[ -n "$SSH_PASS" ]]; then sshpass -p "$SSH_PASS" ssh "${SSH_OPTS[@]}" "$SSH_USER@$VM106_IP" "$cmd"; else ssh "${SSH_OPTS[@]}" "$SSH_USER@$VM106_IP" "$cmd"; fi
}
run_scp() {
  if [[ -n "$SSH_PASS" ]]; then sshpass -p "$SSH_PASS" scp "${SSH_OPTS[@]}" "$@"; else scp "${SSH_OPTS[@]}" "$@"; fi
}

run_ssh "rm -rf '$REMOTE_DIR' && mkdir -p '$REMOTE_ASSETS'"
run_scp "$TMP_LOCAL" "$SSH_USER@$VM106_IP:$REMOTE_SCRIPT" >/dev/null
run_scp "$ASSET_DIR"/* "$SSH_USER@$VM106_IP:$REMOTE_ASSETS/" >/dev/null

REMOTE_ENV="MODE_B64='$MODE_B64' IMMICH_HTTP_URL_B64='$IMMICH_HTTP_URL_B64' ASSET_SOURCE='$REMOTE_ASSETS'"
if [[ -n "$SSH_PASS" ]]; then
  run_ssh "chmod 600 '$REMOTE_SCRIPT'; echo '$SSH_PASS' | sudo -S -p '' env $REMOTE_ENV bash '$REMOTE_SCRIPT'; rc=\$?; rm -rf '$REMOTE_DIR'; exit \$rc"
else
  run_ssh "chmod 600 '$REMOTE_SCRIPT'; sudo env $REMOTE_ENV bash '$REMOTE_SCRIPT'; rc=\$?; rm -rf '$REMOTE_DIR'; exit \$rc"
fi

rm -f "$TMP_LOCAL"

echo
echo "Next steps:"
echo "1) Close every Immich tab in Chrome/Firefox."
echo "2) Open http://192.168.50.106:2283 again."
echo "3) If the title still says Immich, run: bash /root/homelab-bacphotos-immich-title-fix-v6/apply-bacphotos-immich-title-fix-v6.sh status"
