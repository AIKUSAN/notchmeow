#!/usr/bin/env bash
# Desktop cat drop (sub-project H): what happens when the big cat is let go after a drag from the notch: attach as today, place on empty desktop, or nothing.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-desktop-drop.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatKittens.swift \
    $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/DesktopCatTrip.swift $APP/DesktopCatLayout.swift $APP/DesktopCatDrop.swift $APP/DesktopCatPacer.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/DesktopCatDropTests.swift \
    -o "$TEST_DIR/desktop-drop-tests"
"$TEST_DIR/desktop-drop-tests"
