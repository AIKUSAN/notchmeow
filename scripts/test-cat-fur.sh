#!/usr/bin/env bash
# Cat fur lines: the seeded strands of all 16 coats against the prototype's (same seeds, counts and first strands), and when they are drawn.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-fur.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatFur.swift \
    tests/CatTestSupport.swift tests/CatFurTests.swift \
    -o "$TEST_DIR/cat-fur-tests"
"$TEST_DIR/cat-fur-tests"
