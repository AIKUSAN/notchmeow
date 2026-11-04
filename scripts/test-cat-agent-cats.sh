#!/usr/bin/env bash
# Cat agent coats: giving an agent its cat (agentCatFor, the dice, Reset to defaults) against agent-cat-cases.json, with the random source the rows name and
# how many numbers each call draws, and the rules the fixture cannot write down (a random source that misbehaves, defaults that count as taken).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-agent-cats.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift \
    tests/CatTestSupport.swift tests/CatAgentCatsTests.swift \
    -o "$TEST_DIR/cat-agent-cats-tests"
"$TEST_DIR/cat-agent-cats-tests"
