#!/usr/bin/env bash
# Cat personality: the six presets, traits to multipliers and idle habits, and the Custom rule against personality-cases.json.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-personality.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/CatMath.swift NotchBuddy/Sources/App/Personality.swift \
    tests/CatTestSupport.swift tests/CatPersonalityTests.swift \
    -o "$TEST_DIR/cat-personality-tests"
"$TEST_DIR/cat-personality-tests"
