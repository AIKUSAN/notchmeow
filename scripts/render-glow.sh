#!/usr/bin/env bash
# Draws the island's hover glow (IslandGlowView) on the compact notch and the open island, on a light and a dark menu bar, into a PNG, without launching NotchMeow (see scripts/render-glow.swift).
#   bash scripts/render-glow.sh --out hover-glow.png [--scale 2] [--angle 40]
# The view is the app's own, on the app's own IslandShape, so this compiles every file of the app except NotchBuddyApp.swift (the app's own @main): about two minutes. It runs in a home folder of
# its own through scripts/render-home-guard.sh, which kills it if it ever opens the real ~/.claude, ~/.gemini or ~/.codex. It touches no preferences.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-render-glow.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
export NM_LOG_DIR="$BUILD_DIR/logs"
mkdir -p "$BUILD_DIR/home"
APP=NotchBuddy/Sources/App
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(find "$APP" -name '*.swift' ! -name NotchBuddyApp.swift | sort)
swiftc -swift-version 6 -suppress-warnings "${FILES[@]}" scripts/render-glow.swift -o "$BUILD_DIR/render-glow"
. scripts/render-home-guard.sh
render_home_guard "$BUILD_DIR/home" "$BUILD_DIR/render-glow" "$@"
