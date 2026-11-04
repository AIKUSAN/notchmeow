#!/usr/bin/env bash
# Sidekick risk rules (explain): every case of tests/fixtures/sidekick/explain-cases.json, and what the fixture cannot write. Pure Foundation; nothing here launches NotchMeow.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-sidekick-explain.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/SidekickText.swift $APP/SidekickExplain.swift \
    tests/CatTestSupport.swift tests/SidekickExplainTests.swift \
    -o "$TEST_DIR/sidekick-explain-tests"
"$TEST_DIR/sidekick-explain-tests"
