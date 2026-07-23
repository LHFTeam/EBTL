#!/bin/bash
# Build the Flutter customer-app for web and capture a screenshot with the
# pre-installed headless Chromium. This is the practical substitute for a
# device emulator in Claude Code on the web (no KVM / no display here).
#
# Usage:
#   .claude/scripts/flutter-web-shot.sh [route] [out.png]
#
#   route   optional deep-link path passed to the app (default "/")
#   out.png output image path (default ./flutter-web-shot.png)
#
# Notes:
#   * --no-web-resources-cdn bundles CanvasKit locally; without it the engine
#     fetches CanvasKit from gstatic.com, which the sandbox proxy blocks and
#     the app renders blank.
#   * Backend API calls to the hosted server are blocked by the proxy, so
#     network-driven screens fall back to their loading/error state. The
#     onboarding/splash screens render fully.
set -euo pipefail

ROUTE="${1:-/}"
OUT="${2:-$PWD/flutter-web-shot.png}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}"
APP_DIR="$PROJECT_DIR/customer-app"
PORT="${FLUTTER_WEB_PORT:-8123}"
WORK="$(mktemp -d)"

command -v flutter >/dev/null 2>&1 || { echo "flutter not on PATH; start a fresh session or run the session-start hook"; exit 1; }

echo "[shot] building web (release, local CanvasKit)…"
(cd "$APP_DIR" && flutter build web --release --no-web-resources-cdn >/dev/null)

echo "[shot] serving build/web on :$PORT"
python3 -m http.server "$PORT" --directory "$APP_DIR/build/web" >"$WORK/httpd.log" 2>&1 &
SRV=$!
trap 'kill "$SRV" 2>/dev/null || true; rm -rf "$WORK"' EXIT
sleep 2

CHROME="$(ls /opt/pw-browsers/chromium-*/chrome-linux/chrome 2>/dev/null | head -1)"
[ -n "$CHROME" ] || { echo "headless Chromium not found under /opt/pw-browsers"; exit 1; }

# Install a Node driver that waits for Flutter's first frame (single-shot
# --screenshot fires before the async engine paints).
echo "[shot] preparing screenshot driver…"
DRIVER_CACHE="${HOME}/.cache/flutter-web-shot"
mkdir -p "$DRIVER_CACHE"
if [ ! -d "$DRIVER_CACHE/node_modules/playwright-core" ]; then
  (cd "$DRIVER_CACHE" && npm init -y >/dev/null 2>&1 && npm i playwright-core@1.49.1 >/dev/null 2>&1)
fi

cat > "$WORK/shot.js" <<'JS'
const { chromium } = require(process.env.DRIVER_CACHE + '/node_modules/playwright-core');
const fs = require('fs');
(async () => {
  const exe = process.env.CHROME;
  const url = process.env.URL;
  const out = process.env.OUT;
  const browser = await chromium.launch({
    executablePath: exe,
    args: ['--no-sandbox','--enable-unsafe-swiftshader','--use-gl=angle','--use-angle=swiftshader','--ignore-gpu-blocklist'],
  });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
  await page.goto(url, { waitUntil: 'load', timeout: 60000 });
  try { await page.waitForSelector('flutter-view, flt-glass-pane, canvas', { timeout: 45000 }); }
  catch (e) { console.log('[shot] flutter surface not detected:', e.message); }
  await page.waitForTimeout(8000);
  await page.screenshot({ path: out });
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
JS

URL="http://localhost:$PORT/index.html#${ROUTE}" \
CHROME="$CHROME" OUT="$OUT" DRIVER_CACHE="$DRIVER_CACHE" \
  node "$WORK/shot.js"

echo "[shot] saved $OUT"
