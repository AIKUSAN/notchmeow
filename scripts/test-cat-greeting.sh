#!/usr/bin/env bash
# The launch greeting timeline, its streaks and the file flight against sequence-cases.json.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-greeting.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatLook.swift \
    $APP/MotionProfiles.swift $APP/CatEngine.swift $APP/CatGreeting.swift $APP/IslandScreenGeometry.swift \
    tests/CatTestSupport.swift tests/CatGreetingTests.swift \
    -o "$TEST_DIR/cat-greeting-tests"
"$TEST_DIR/cat-greeting-tests"
