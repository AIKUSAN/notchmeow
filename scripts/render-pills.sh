#!/usr/bin/env bash
# Draws the island's agent pills (AgentPill): Claude Code, Claude Desktop and two agents, into a PNG, without launching NotchMeow (see scripts/render-pills.swift).
#   bash scripts/render-pills.sh --out pills.png [--scale 2]
# AgentPill reads the app's AppState, so this compiles every file of the app except NotchBuddyApp.swift (the app's own @main): about seven minutes. It runs in a home folder of its own through
# scripts/render-home-guard.sh, which kills it if it ever opens the real ~/.claude, ~/.gemini or ~/.codex.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-render-pills.XXXXXX")"
REAL_HOME="$HOME"
cleanup() {
    rm -rf "$BUILD_DIR"
    defaults delete render-pills > /dev/null 2>&1 || true
    rm -f "$REAL_HOME/Library/Preferences/render-pills.plist"
}
trap cleanup EXIT
export NM_LOG_DIR="$BUILD_DIR/logs"
mkdir -p "$BUILD_DIR/home"
APP=NotchBuddy/Sources/App
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(find "$APP" -name '*.swift' ! -name NotchBuddyApp.swift | sort)
swiftc -swift-version 6 -suppress-warnings "${FILES[@]}" scripts/render-pills.swift -o "$BUILD_DIR/render-pills"
. scripts/render-home-guard.sh
render_home_guard "$BUILD_DIR/home" "$BUILD_DIR/render-pills" "$@"
