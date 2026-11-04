#!/usr/bin/env bash
# Desktop cat layout (sub-project H): AppKit's screens as the contract's, the window around the cat for each size and side, which side the kittens go on and the shape of the body that takes the mouse.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-desktop-layout.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatKittens.swift \
    $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/DesktopCatTrip.swift $APP/DesktopCatLayout.swift $APP/DesktopCatDrop.swift $APP/DesktopCatPacer.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/DesktopCatLayoutTests.swift \
    -o "$TEST_DIR/desktop-layout-tests"
"$TEST_DIR/desktop-layout-tests"
