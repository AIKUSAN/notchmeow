#!/usr/bin/env bash
# The cat engine on a fake clock and a seeded rand against motion-cases.json (rest, enters, emotes, ambient habits) and
# sequence-cases.json (the file catch, the zoomies and wake rules).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-engine.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatLook.swift \
    $APP/MotionProfiles.swift $APP/CatEngine.swift \
    tests/CatTestSupport.swift tests/CatEngineSupport.swift tests/CatEngineTests.swift \
    -o "$TEST_DIR/cat-engine-tests"
"$TEST_DIR/cat-engine-tests"
