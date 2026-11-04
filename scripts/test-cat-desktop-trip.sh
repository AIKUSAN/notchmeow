#!/usr/bin/env bash
# Desktop cat trip (sub-project H): the seven phases and desktopStep (63 pairs and input that is neither), the trips, desktopFlightAt and the flight's clock (a turn does not make
# the cat jump), desktopFps and desktopKittenSlots against desktop-cases.json, and what the fixture cannot write (NaN, infinity, a clock that is not a number).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-desktop-trip.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatKittens.swift \
    $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/DesktopCatTrip.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/DesktopCatTripTests.swift \
    -o "$TEST_DIR/desktop-trip-tests"
"$TEST_DIR/desktop-trip-tests"
