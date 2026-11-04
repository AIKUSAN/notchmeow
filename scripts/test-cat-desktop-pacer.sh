#!/usr/bin/env bash
# Desktop cat pacer (sub-project H): the frame-rate target as one timer that is re-armed only when it changes, and what hides the cat.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-desktop-pacer.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatKittens.swift \
    $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/DesktopCatTrip.swift $APP/DesktopCatLayout.swift $APP/DesktopCatDrop.swift $APP/DesktopCatPacer.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/DesktopCatPacerTests.swift \
    -o "$TEST_DIR/desktop-pacer-tests"
"$TEST_DIR/desktop-pacer-tests"
