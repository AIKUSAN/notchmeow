#!/usr/bin/env bash
# The quick actions' pure state (F3a-mac, Task 8): where a quick action's text comes from, the cap on a huge clipboard, the result card's states, the
# latest-run gate and the first turn of a quick Explain. Pure Foundation; no pasteboard, no app, no clock.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-companion-quick.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CompanionChrome.swift $APP/CompanionQuickState.swift \
    tests/CatTestSupport.swift tests/CompanionQuickStateTests.swift \
    -o "$TEST_DIR/companion-quick-tests"
"$TEST_DIR/companion-quick-tests"
