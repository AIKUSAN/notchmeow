#!/usr/bin/env bash
# Draws the approval card of the island (ApprovalView) with the big cat beside it into a PNG, without launching NotchMeow (see scripts/render-approval-card.swift).
#   bash scripts/render-approval-card.sh --out approval-card.png [--scale 2] [--command "npm test"] [--line "..."] [--risk high] [--explain]
# ApprovalView reads the app's AppState, so this script compiles every file of the app except NotchBuddyApp.swift (the app's own @main): about two minutes. AppState is made
# (it reads UserDefaults, which for this tool is a domain of its own, and ~/.claude/settings.json, which is in the empty home folder below: scripts/render-home-guard.sh points
# Foundation at that folder and kills the tool if it ever opens the real ~/.claude, ~/.gemini or ~/.codex) and it saves a few defaults into
# that domain: the script deletes them when it ends, and never touches NotchMeow's own preferences.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-render-approval.XXXXXX")"
REAL_HOME="$HOME"
cleanup() {
    rm -rf "$BUILD_DIR"
    defaults delete render-approval-card > /dev/null 2>&1 || true
    rm -f "$REAL_HOME/Library/Preferences/render-approval-card.plist"
}
trap cleanup EXIT
export NM_LOG_DIR="$BUILD_DIR/logs"
mkdir -p "$BUILD_DIR/home"
APP=NotchBuddy/Sources/App
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(find "$APP" -name '*.swift' ! -name NotchBuddyApp.swift | sort)
swiftc -swift-version 6 -suppress-warnings "${FILES[@]}" scripts/render-approval-card.swift -o "$BUILD_DIR/render-approval-card"
. scripts/render-home-guard.sh
render_home_guard "$BUILD_DIR/home" "$BUILD_DIR/render-approval-card" "$@"
