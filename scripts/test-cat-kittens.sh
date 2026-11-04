#!/usr/bin/env bash
# Cat kittens: the reducer (CatKittens.step), the order, the view, the places and the slots against kitten-cases.json, and what the fixture cannot write (a time that is
# not finite, a fuzz of events that must keep the list's invariants).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-kittens.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatKittens.swift \
    tests/CatTestSupport.swift tests/CatKittensTests.swift \
    -o "$TEST_DIR/cat-kittens-tests"
"$TEST_DIR/cat-kittens-tests"
