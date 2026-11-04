#!/usr/bin/env bash
# Stored conversations' pure rules (F3a-mac, Task 5): which chat rows a stored conversation keeps, the model's text for a stored message (file names only)
# and the day a row shows. Pure Foundation; no file, no default, no clock (the times are fixed in the test).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-companion-conversations.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CompanionText.swift $APP/CompanionRecords.swift $APP/CompanionConversations.swift \
    $APP/ProjectsRules.swift $APP/ProjectsRegistry.swift \
    tests/CatTestSupport.swift tests/CompanionConversationTests.swift \
    -o "$TEST_DIR/companion-conversation-tests"
"$TEST_DIR/companion-conversation-tests"
