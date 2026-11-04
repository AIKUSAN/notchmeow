#!/usr/bin/env bash
# Draws focus awareness's pictures (the amber dot, the compact dots and the note) into one PNG, without launching NotchMeow (see scripts/render-focus-aware.swift).
#   bash scripts/render-focus-aware.sh --out focus-aware.png [--scale 2]
# The views read the app's AppState, so this compiles every file of the app except NotchBuddyApp.swift (the app's own @main): about seven minutes. It runs in a home folder of its own through
# scripts/render-home-guard.sh, which kills it if it ever opens the real ~/.claude, ~/.gemini or ~/.codex.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-render-focus-aware.XXXXXX")"
REAL_HOME="$HOME"
cleanup() {
    rm -rf "$BUILD_DIR"
    defaults delete render-focus-aware > /dev/null 2>&1 || true
    rm -f "$REAL_HOME/Library/Preferences/render-focus-aware.plist"
}
trap cleanup EXIT
export NM_LOG_DIR="$BUILD_DIR/logs"
mkdir -p "$BUILD_DIR/home"
APP=NotchBuddy/Sources/App
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(find "$APP" -name '*.swift' ! -name NotchBuddyApp.swift | sort)
swiftc -swift-version 6 -suppress-warnings "${FILES[@]}" scripts/render-focus-aware.swift -o "$BUILD_DIR/render-focus-aware"
. scripts/render-home-guard.sh
render_home_guard "$BUILD_DIR/home" "$BUILD_DIR/render-focus-aware" "$@"
