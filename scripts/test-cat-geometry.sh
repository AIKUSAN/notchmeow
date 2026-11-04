#!/usr/bin/env bash
# Cat geometry: outlines, anchors, the face warp, gaze maths and ear headroom against geometry-cases.json and warp-cases.json.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-geometry.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/CatMath.swift NotchBuddy/Sources/App/CatPresets.swift NotchBuddy/Sources/App/CatGeometry.swift \
    tests/CatTestSupport.swift tests/CatGeometryTests.swift \
    -o "$TEST_DIR/cat-geometry-tests"
"$TEST_DIR/cat-geometry-tests"
