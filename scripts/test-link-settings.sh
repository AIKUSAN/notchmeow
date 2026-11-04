#!/usr/bin/env bash
# The link's settings (LinkSettings: visible on the network, off by default; the device name) and the device list (LinkDirectory). Foundation only; a dictionary stands in for UserDefaults.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-link-settings.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/LinkBytes.swift $APP/LinkName.swift $APP/LinkFrames.swift $APP/LinkSettings.swift $APP/LinkKeychain.swift \
    tests/CatTestSupport.swift tests/LinkSettingsTests.swift \
    -o "$TEST_DIR/link-settings-tests"
"$TEST_DIR/link-settings-tests"
