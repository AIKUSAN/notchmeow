#!/usr/bin/env bash
# Desktop cat dev panel (sub-project H): the Debug-only Desktop section's model: an alert flight on a mock desktop (the surprised beat, the flight into the notch, the cat in the notch, the flight back, a turn
# without a jump) and the frame rate the rule picks, driven by the same pure rules the real desktop cat uses. Compiled with DEBUG, like the cat panel's own test.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-desktop-devpanel.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 -D DEBUG \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/Wardrobe.swift $APP/CatOutfit.swift $APP/CatOutfitDraw.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatKittens.swift $APP/CatKittenDraw.swift $APP/CatIslandLayout.swift \
    $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/DesktopCatTrip.swift $APP/DesktopCatPacer.swift $APP/DesktopCatDraw.swift $APP/DesktopCatDevModel.swift \
    tests/CatTestSupport.swift tests/DesktopCatDevModelTests.swift \
    -o "$TEST_DIR/desktop-devpanel-tests"
"$TEST_DIR/desktop-devpanel-tests"
