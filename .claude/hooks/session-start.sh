#!/bin/bash
# SessionStart hook: make the Flutter SDK available for the customer-app.
#
# Runs only in Claude Code on the web (remote) sessions, where the container
# starts fresh each time. It installs a pinned stable Flutter that ships the
# Dart SDK required by customer-app (Dart ^3.12.0 -> Flutter 3.44.7 / Dart
# 3.12.2), puts it on PATH for the session, and warms `flutter pub get`.
#
# NOTE: this environment has no KVM / hardware virtualization and no display,
# so Android/iOS emulators are not usable here. To *see* the app, build the
# web target and screenshot it with the pre-installed headless Chromium — see
# .claude/scripts/flutter-web-shot.sh.
set -euo pipefail

# Web sessions only; a local machine has its own Flutter install.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

FLUTTER_VERSION="3.44.7"
FLUTTER_DIR="${FLUTTER_HOME:-$HOME/flutter}"
FLUTTER_BIN="$FLUTTER_DIR/bin"

log() { echo "[flutter-setup] $*"; }

if [ ! -x "$FLUTTER_BIN/flutter" ]; then
  log "Installing Flutter $FLUTTER_VERSION -> $FLUTTER_DIR"
  url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/flutter.tar.xz" "$url"
  mkdir -p "$(dirname "$FLUTTER_DIR")"
  tar -xJf "$tmp/flutter.tar.xz" -C "$(dirname "$FLUTTER_DIR")"
  rm -rf "$tmp"
else
  log "Flutter already present at $FLUTTER_DIR"
fi

export PATH="$FLUTTER_BIN:$PATH"
# The container runs as root; Flutter's git checks need the dir marked safe.
git config --global --add safe.directory "$FLUTTER_DIR" 2>/dev/null || true

# Persist PATH for the rest of the session.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$FLUTTER_BIN:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi

# Enable the web target (used for headless previews).
flutter config --enable-web >/dev/null 2>&1 || true

# Warm dependencies so the first analyze/test/build is fast.
if [ -f "$CLAUDE_PROJECT_DIR/customer-app/pubspec.yaml" ]; then
  log "Running flutter pub get in customer-app"
  (cd "$CLAUDE_PROJECT_DIR/customer-app" && flutter pub get) || \
    log "pub get failed (continuing; run it manually if needed)"
fi

log "Flutter ready: $("$FLUTTER_BIN/flutter" --version 2>/dev/null | head -1)"
