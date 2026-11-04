#!/usr/bin/env bash
# Companion brain (F3a-mac, Task 4): the companion's system prompt reaches the model in the request the fake local server logs, "Right now" follows
# See my sessions, no path reaches the model, and what a turn sends keeps no file's text. Runs against tests/fake_local_llm.py on 127.0.0.1 only.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-companion-brain.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 -D DEBUG \
    $APP/AI/Core/*.swift \
    $APP/AppLog.swift \
    $APP/CompanionText.swift $APP/CompanionRecords.swift $APP/CompanionPrompt.swift $APP/CompanionRightNow.swift $APP/CompanionTurn.swift \
    $APP/ProjectsRules.swift $APP/ProjectsRegistry.swift $APP/ProjectsSnapshot.swift $APP/HookOrigin.swift \
    tests/AITestSupport.swift tests/CompanionBrainTests.swift \
    -o "$TEST_DIR/companion-brain-tests"
"$TEST_DIR/companion-brain-tests"
