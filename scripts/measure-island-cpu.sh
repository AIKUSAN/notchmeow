#!/usr/bin/env bash
# How much CPU the island's own SwiftUI costs in a given state, without launching NotchMeow (see scripts/measure-island-cpu.swift).
#   bash scripts/measure-island-cpu.sh [--state compact|overview|approval|approval-high|question|all] [--seconds 8]
# IslandRootView reads the app's AppState, so this compiles every file of the app except NotchBuddyApp.swift (the app's own @main): about seven minutes (-O: the numbers should be near the Release build's, not the unoptimised Debug ones). It runs in a home folder of
# its own through scripts/render-home-guard.sh, which kills it if it ever opens the real ~/.claude, ~/.gemini or ~/.codex. It touches no preferences.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-measure-island-cpu.XXXXXX")"
REAL_HOME="$HOME"
cleanup() {
    rm -rf "$BUILD_DIR"
    defaults delete measure-island-cpu > /dev/null 2>&1 || true
    rm -f "$REAL_HOME/Library/Preferences/measure-island-cpu.plist"
}
trap cleanup EXIT
export NM_LOG_DIR="$BUILD_DIR/logs"
mkdir -p "$BUILD_DIR/home"
APP=NotchBuddy/Sources/App
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(find "$APP" -name '*.swift' ! -name NotchBuddyApp.swift | sort)
swiftc -O -swift-version 6 -suppress-warnings "${FILES[@]}" scripts/measure-island-cpu.swift -o "$BUILD_DIR/measure-island-cpu"
. scripts/render-home-guard.sh
render_home_guard "$BUILD_DIR/home" "$BUILD_DIR/measure-island-cpu" "$@"
