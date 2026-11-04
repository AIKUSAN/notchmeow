#!/usr/bin/env bash
# Cat small eyes: the geometry of the coloured eyes of the compact detail level (CatSmallEye) against small-eye-cases.json, a real NaN, the floors,
# and that the pupil never leaves the iris.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-small-eye.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatSmallEye.swift \
    tests/CatTestSupport.swift tests/CatSmallEyeTests.swift \
    -o "$TEST_DIR/cat-small-eye-tests"
"$TEST_DIR/cat-small-eye-tests"
