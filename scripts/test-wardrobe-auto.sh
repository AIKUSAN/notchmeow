#!/usr/bin/env bash
# Wardrobe Auto (sub-project I): Easter (Meeus/Jones/Butcher), the five dated rules in their order, resolve, the date and the seconds to midnight (daylight saving included) and the
# clock with its ONE one-shot timer, against wardrobe-cases.json, and what the fixture cannot write (a timer that fires early, one that fires days late, a date override).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-wardrobe-auto.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/Wardrobe.swift $APP/WardrobeSettings.swift $APP/WardrobeAuto.swift $APP/CatSettings.swift $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift \
    tests/CatTestSupport.swift tests/WardrobeAutoTests.swift \
    -o "$TEST_DIR/wardrobe-auto-tests"
"$TEST_DIR/wardrobe-auto-tests"
