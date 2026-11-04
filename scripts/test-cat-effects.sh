#!/usr/bin/env bash
# The cat's drawing kit and effects: colours, text, badge, particles, paws, hairballs, glow, trails and the dance, drawn into bitmaps.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-effects.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    tests/CatTestSupport.swift tests/CatBitmapSupport.swift tests/CatEffectsTests.swift \
    -o "$TEST_DIR/cat-effects-tests"
"$TEST_DIR/cat-effects-tests"
