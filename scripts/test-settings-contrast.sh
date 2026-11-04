#!/usr/bin/env bash
# Settings help text: its colour reads at 4.5:1 or better in light and dark, on the system backgrounds a card sits on. Nothing here launches NotchMeow.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-settings-contrast.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/SettingsColors.swift \
    tests/CatTestSupport.swift tests/SettingsContrastTests.swift \
    -o "$TEST_DIR/settings-contrast-tests"
"$TEST_DIR/settings-contrast-tests"
