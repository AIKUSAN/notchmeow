#!/usr/bin/env bash
# Sidekick notes (held, shown, dropped, replaced) and the one one-shot clock, driven by hand. Pure Foundation.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-sidekick-notes.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/SidekickText.swift $APP/SidekickExplain.swift $APP/SidekickLedger.swift $APP/SidekickStuck.swift $APP/SidekickRecap.swift $APP/SidekickSettings.swift $APP/SidekickPresence.swift $APP/SidekickNotes.swift \
    tests/CatTestSupport.swift tests/SidekickNotesTests.swift \
    -o "$TEST_DIR/sidekick-notes-tests"
"$TEST_DIR/sidekick-notes-tests"
