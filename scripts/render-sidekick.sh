#!/usr/bin/env bash
# Draws the sidekick's notes (SidekickView) with the big cat beside them into a PNG, without launching NotchMeow (see scripts/render-sidekick.swift): a recap after a lock, a nudge for a loop, a
# nudge for a request nobody is looking at and a recap of four agents, each made by the real engine on a clock by hand; and, with --settings-out, Settings → Sidekick.
#   bash scripts/render-sidekick.sh --out sidekick-notes.png [--scale 2] [--settings-out sidekick-settings.png]
# SidekickView reads the app's AppState, so this script compiles every file of the app except NotchBuddyApp.swift (the app's own @main): about two minutes. AppState is made (it reads UserDefaults,
# which for this tool is a domain of its own, and ~/.claude/settings.json, which is in the empty home folder below: scripts/render-home-guard.sh points Foundation at that folder and kills the tool
# if it ever opens the real ~/.claude, ~/.gemini or ~/.codex) and it saves a few defaults into that domain: the script deletes them when it ends, and never touches NotchMeow's own preferences.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-render-sidekick.XXXXXX")"
REAL_HOME="$HOME"
cleanup() {
    rm -rf "$BUILD_DIR"
    defaults delete render-sidekick > /dev/null 2>&1 || true
    rm -f "$REAL_HOME/Library/Preferences/render-sidekick.plist"
}
trap cleanup EXIT
export NM_LOG_DIR="$BUILD_DIR/logs"
mkdir -p "$BUILD_DIR/home"
APP=NotchBuddy/Sources/App
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(find "$APP" -name '*.swift' ! -name NotchBuddyApp.swift | sort)
swiftc -swift-version 6 -suppress-warnings "${FILES[@]}" scripts/render-sidekick.swift -o "$BUILD_DIR/render-sidekick"
. scripts/render-home-guard.sh
render_home_guard "$BUILD_DIR/home" "$BUILD_DIR/render-sidekick" "$@"
