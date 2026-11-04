#!/usr/bin/env bash
# Desktop cat input (sub-project H): a click that waits one double-click interval, the double-click, the drag, the right-click menu, kittens arriving or leaving and the notch spot.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-desktop-input.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatKittens.swift \
    $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/DesktopCatTrip.swift $APP/Wardrobe.swift $APP/WardrobeAuto.swift $APP/DesktopCatLayout.swift $APP/DesktopCatInput.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/DesktopCatInputTests.swift \
    -o "$TEST_DIR/desktop-input-tests"
"$TEST_DIR/desktop-input-tests"
