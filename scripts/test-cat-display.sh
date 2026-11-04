#!/usr/bin/env bash
# Cat display settings: the clean-up of what Settings → Cat → Display saves (cleanDisplaySettings, cleanPair, cleanAgentCats, the pill-ID rules) against
# display-cases.json, and the UserDefaults keys through an injected dictionary store (no UserDefaults suite).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-cat-display.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/CatDisplayTests.swift \
    -o "$TEST_DIR/cat-display-tests"
"$TEST_DIR/cat-display-tests"
