#!/usr/bin/env bash
# The cat renderer draws every coat, size, pose and eye shape without a blank or a crash, deterministically, and keeps its ears in the strip.
# (There are no pixel tests: the look is checked by eye on the contact sheet from scripts/render-cats.sh.)
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-renderer.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/Wardrobe.swift $APP/CatOutfit.swift $APP/CatOutfitDraw.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift tests/CatEngineSupport.swift \
    $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift $APP/IslandScreenGeometry.swift \
    tests/CatTestSupport.swift tests/CatBitmapSupport.swift tests/CatRendererTests.swift \
    -o "$TEST_DIR/cat-renderer-tests"
"$TEST_DIR/cat-renderer-tests"
