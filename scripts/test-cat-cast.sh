#!/usr/bin/env bash
# Cat cast: which cat appears where in each display mode (CatCast.of, busyRank) against cast-cases.json, and the inputs the fixture cannot write (a time that is
# not a number, a hostile island).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-cast.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatCast.swift \
    tests/CatTestSupport.swift tests/CatCastTests.swift \
    -o "$TEST_DIR/cat-cast-tests"
"$TEST_DIR/cat-cast-tests"
