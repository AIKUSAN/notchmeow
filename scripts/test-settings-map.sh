#!/usr/bin/env bash
# Settings control map: every control has a home, every stored key keeps its name and store, and the Windows starting file (tests/fixtures/settings/controls.json) matches the Swift table.
# Nothing here launches NotchMeow.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-settings-map.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/SettingsRoute.swift $APP/SettingsMap.swift \
    tests/CatTestSupport.swift tests/SettingsMapTests.swift \
    -o "$TEST_DIR/settings-map-tests"
"$TEST_DIR/settings-map-tests"
