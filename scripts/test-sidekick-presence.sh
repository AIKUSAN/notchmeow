#!/usr/bin/env bash
# Sidekick presence rule and show gate (presenceStep, shouldShow): presence-cases.json and show-cases.json, and what they cannot write. Pure Foundation.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-sidekick-presence.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/SidekickText.swift $APP/SidekickSettings.swift $APP/SidekickPresence.swift \
    tests/CatTestSupport.swift tests/SidekickPresenceTests.swift \
    -o "$TEST_DIR/sidekick-presence-tests"
"$TEST_DIR/sidekick-presence-tests"
