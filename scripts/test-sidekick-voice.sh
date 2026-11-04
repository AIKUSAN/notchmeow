#!/usr/bin/env bash
# Sidekick local voice: the sanity check (voice-cases.json), the prompt, and the one-shot request to a local model against fake providers that record every request. AI core only; no app.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-sidekick-voice.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/AI/Core/*.swift $APP/AppLog.swift \
    $APP/SidekickText.swift $APP/SidekickExplain.swift $APP/SidekickLedger.swift $APP/SidekickStuck.swift $APP/SidekickRecap.swift $APP/SidekickVoice.swift $APP/SidekickVoiceLocal.swift \
    tests/CatTestSupport.swift tests/SidekickVoiceTests.swift \
    -o "$TEST_DIR/sidekick-voice-tests"
"$TEST_DIR/sidekick-voice-tests"
