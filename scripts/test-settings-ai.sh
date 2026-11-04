#!/usr/bin/env bash
# Settings AI rows: which rows show, their words and chips, Make main, and which row is main. Nothing here launches NotchMeow or reads a key.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-settings-ai.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/AI/Core/*.swift \
    $APP/AppLog.swift \
    $APP/SettingsStatus.swift $APP/SettingsAI.swift \
    tests/CatTestSupport.swift tests/SettingsAITests.swift \
    -o "$TEST_DIR/settings-ai-tests"
"$TEST_DIR/settings-ai-tests"
