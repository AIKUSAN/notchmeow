#!/usr/bin/env bash
# Draws the link's pictures (sub-project G2) without launching NotchMeow (see scripts/render-link.swift).
#   bash scripts/render-link.sh --cards --out DIR     the pairing card, the Accept card, the progress and the end of a transfer, each in the island
#   bash scripts/render-link.sh --devices --out DIR   Settings → Devices: off, on with machines, and the problem notes
#   bash scripts/render-link.sh --shelf --out DIR     the shelf's bar with the "To a device" button and the status of a send, and the bar with the machines to send to (chips)
# The cards use the island's CardBackground and buttons, which sit in IslandViewContent.swift, so this compiles every file of the app but NotchBuddyApp.swift (about two minutes), as
# render-approval-card.sh does, and runs in a home folder of its own (scripts/render-home-guard.sh kills it if it opens the real ~/.claude, ~/.gemini or ~/.codex). Nothing is launched or listened to.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-render-link.XXXXXX")"
REAL_HOME="$HOME"
cleanup() {
    rm -rf "$BUILD_DIR"
    defaults delete render-link > /dev/null 2>&1 || true
    rm -f "$REAL_HOME/Library/Preferences/render-link.plist"
}
trap cleanup EXIT
export NM_LOG_DIR="$BUILD_DIR/logs"
mkdir -p "$BUILD_DIR/home"
APP=NotchBuddy/Sources/App
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(find "$APP" -name '*.swift' ! -name NotchBuddyApp.swift | sort)
swiftc -swift-version 6 -suppress-warnings -D DEBUG "${FILES[@]}" scripts/render-link.swift -o "$BUILD_DIR/render-link"
. scripts/render-home-guard.sh
render_home_guard "$BUILD_DIR/home" "$BUILD_DIR/render-link" "$@"
