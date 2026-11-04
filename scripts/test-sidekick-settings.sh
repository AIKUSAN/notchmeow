#!/usr/bin/env bash
# Sidekick dismissal memory and stored settings (dismiss, unmute, SidekickSettings.clean, the UserDefaults keys): dismiss-cases.json and settings-cases.json, and what they cannot write.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-sidekick-settings.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/SidekickSettings.swift $APP/SidekickStore.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/SidekickSettingsTests.swift \
    -o "$TEST_DIR/sidekick-settings-tests"
"$TEST_DIR/sidekick-settings-tests"
