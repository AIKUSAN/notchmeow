#!/usr/bin/env bash
# Draws the music pill's checkpoint rows (MusicCardView and MusicPill in IslandViewContent.swift) into a PNG, without launching NotchMeow or any music app (see scripts/render-music.swift).
#   bash scripts/render-music.sh --out music.png [--scale 2]
# The views read the app's AppState and MusicController, so this compiles every file of the app except NotchBuddyApp.swift (the app's own @main): about seven minutes. It runs in a
# home folder of its own through scripts/render-home-guard.sh, which kills it if it ever opens the real ~/.claude, ~/.gemini or ~/.codex. The rows are fed through
# MusicController.receive and noteDenied directly; no script is sent to any app.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-render-music.XXXXXX")"
REAL_HOME="$HOME"
cleanup() {
    rm -rf "$BUILD_DIR"
    defaults delete render-music > /dev/null 2>&1 || true
    rm -f "$REAL_HOME/Library/Preferences/render-music.plist"
}
trap cleanup EXIT
export NM_LOG_DIR="$BUILD_DIR/logs"
mkdir -p "$BUILD_DIR/home"
APP=NotchBuddy/Sources/App
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(find "$APP" -name '*.swift' ! -name NotchBuddyApp.swift | sort)
swiftc -swift-version 6 -suppress-warnings "${FILES[@]}" scripts/render-music.swift -o "$BUILD_DIR/render-music"
. scripts/render-home-guard.sh
render_home_guard "$BUILD_DIR/home" "$BUILD_DIR/render-music" "$@"
