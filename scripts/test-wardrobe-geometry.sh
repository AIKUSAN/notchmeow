#!/usr/bin/env bash
# Wardrobe geometry (sub-project I): outfitEdge, outfitRoom, outfitAnchors, the shapes of all 16 outfits (outfitGeometry), their digests on all 16 coats at four sizes, the bell, bandana
# and scarf over each collar style, the detail cut and the compact notch's floors, against wardrobe-cases.json.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-wardrobe-geometry.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Wardrobe.swift $APP/CatOutfit.swift \
    tests/CatTestSupport.swift tests/WardrobeGeometryTests.swift \
    -o "$TEST_DIR/wardrobe-geometry-tests"
"$TEST_DIR/wardrobe-geometry-tests"
