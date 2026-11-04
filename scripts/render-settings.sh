#!/usr/bin/env bash
# Draws the restyled Settings window without launching NotchMeow (see scripts/render-settings.swift): the shell, every page and tab at 415, 720 and 1100 pt, or the kit's pieces.
#   bash scripts/render-settings.sh [--out DIR] [--page P] [--tab T] [--width W] [--light] [--appstore] [--stress] [--states empty|ready|error] [--kit]
# About two minutes (the whole app is compiled, as render-link.sh does, because the page views use the app's value types); nothing is launched; no Keychain item, real path or user
# name is read. It runs in a home folder of its own (scripts/render-home-guard.sh kills it if it opens the real ~/.claude, ~/.gemini or ~/.codex). --appstore compiles with
# -D APPSTORE instead of -D DEBUG.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-render-settings.XXXXXX")"
REAL_HOME="$HOME"
cleanup() {
    rm -rf "$BUILD_DIR"
    defaults delete render-settings > /dev/null 2>&1 || true
    rm -f "$REAL_HOME/Library/Preferences/render-settings.plist"
}
trap cleanup EXIT
export NM_LOG_DIR="$BUILD_DIR/logs"
mkdir -p "$BUILD_DIR/home"
DEFINE=DEBUG
for arg in "$@"; do [ "$arg" = "--appstore" ] && DEFINE=APPSTORE; done
APP=NotchBuddy/Sources/App
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(find "$APP" -name '*.swift' ! -name NotchBuddyApp.swift | sort)
swiftc -swift-version 6 -suppress-warnings -D "$DEFINE" "${FILES[@]}" scripts/render-settings.swift -o "$BUILD_DIR/render-settings"
. scripts/render-home-guard.sh
render_home_guard "$BUILD_DIR/home" "$BUILD_DIR/render-settings" "$@"
