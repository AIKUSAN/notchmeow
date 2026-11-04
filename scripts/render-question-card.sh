#!/usr/bin/env bash
# Draws the island's question card (QuestionView) with made-up option descriptions into a PNG, without launching NotchMeow (see scripts/render-question-card.swift).
#   bash scripts/render-question-card.sh --out question-card.png [--scale 2] [--plain]
# ApprovalView-style: QuestionView reads the app's AppState, so this compiles every file of the app except NotchBuddyApp.swift (the app's own @main): about two minutes. It runs in a home folder of
# its own through scripts/render-home-guard.sh, which kills it if it ever opens the real ~/.claude, ~/.gemini or ~/.codex. It touches no preferences.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-render-question-card.XXXXXX")"
REAL_HOME="$HOME"
cleanup() {
    rm -rf "$BUILD_DIR"
    defaults delete render-question-card > /dev/null 2>&1 || true
    rm -f "$REAL_HOME/Library/Preferences/render-question-card.plist"
}
trap cleanup EXIT
export NM_LOG_DIR="$BUILD_DIR/logs"
mkdir -p "$BUILD_DIR/home"
APP=NotchBuddy/Sources/App
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(find "$APP" -name '*.swift' ! -name NotchBuddyApp.swift | sort)
swiftc -swift-version 6 -suppress-warnings "${FILES[@]}" scripts/render-question-card.swift -o "$BUILD_DIR/render-question-card"
. scripts/render-home-guard.sh
render_home_guard "$BUILD_DIR/home" "$BUILD_DIR/render-question-card" "$@"
