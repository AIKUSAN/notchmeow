#!/usr/bin/env bash
# Sidekick leak test: a marker word planted in a command, a prompt, a parent folder, an assistant message, a tool's output, a file's contents and a transcript path never reaches a log, a note, a line,
# a ledger, a status answer or a non-local provider; the local fake gets one request with the template's words only. Compiles the AI core and the sidekick's files (no app).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-sidekick-leak.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
mkdir -p "$NM_LOG_DIR"

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/AI/Core/*.swift $APP/AppLog.swift \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift \
    $APP/SidekickText.swift $APP/SidekickExplain.swift $APP/SidekickLedger.swift $APP/SidekickStuck.swift $APP/SidekickRecap.swift $APP/SidekickSettings.swift $APP/SidekickStore.swift \
    $APP/SidekickPresence.swift $APP/SidekickNotes.swift $APP/SidekickVoice.swift $APP/SidekickVoiceLocal.swift $APP/SidekickEngine.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/SidekickLeakTests.swift \
    -o "$TEST_DIR/sidekick-leak-tests"
"$TEST_DIR/sidekick-leak-tests"
