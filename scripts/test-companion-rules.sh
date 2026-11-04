#!/usr/bin/env bash
# Companion records, settings, quick actions, chat sizing and the folder words (F3a-mac, Task 2): titleOf, conversationClean, conversationsKeep,
# cleanCompanionSettings and quickRequest / quickResultClean, replayed against tests/fixtures/companion/conversation-cases.json, settings-cases.json and
# quick-cases.json, and the rules those fixtures cannot write. Pure Foundation; nothing of the Claude Code engine.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-companion-rules.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
# -O: the 200 ms rows measure the rules at optimized speed (the app's Debug build is -Onone and the rules never see 100,000 characters there).
swiftc -O -swift-version 6 \
    $APP/CompanionText.swift $APP/CompanionRecords.swift $APP/CompanionQuick.swift $APP/ChatSizing.swift $APP/CompanionChrome.swift \
    $APP/ProjectsRules.swift $APP/ProjectsRegistry.swift \
    tests/CatTestSupport.swift tests/CompanionRulesTests.swift \
    -o "$TEST_DIR/companion-rules-tests"
"$TEST_DIR/companion-rules-tests"
