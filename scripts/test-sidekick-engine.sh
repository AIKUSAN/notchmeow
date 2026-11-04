#!/usr/bin/env bash
# Sidekick engine: scripted runs of the whole flow (recap after a lock, nudges, held and dropped notes, mute and Unmute, the one clock) with a clock and a timer by hand. Compiled without AppState or AppKit.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-sidekick-engine.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift \
    $APP/SidekickText.swift $APP/SidekickExplain.swift $APP/SidekickLedger.swift $APP/SidekickStuck.swift $APP/SidekickRecap.swift $APP/SidekickSettings.swift $APP/SidekickStore.swift $APP/SidekickPresence.swift $APP/SidekickNotes.swift $APP/SidekickEngine.swift \
    tests/CatTestSupport.swift tests/CatSettingsSupport.swift tests/SidekickEngineTests.swift \
    -o "$TEST_DIR/sidekick-engine-tests"
"$TEST_DIR/sidekick-engine-tests"
