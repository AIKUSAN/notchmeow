#!/usr/bin/env bash
# Sidekick hook adapter and ledger (eventFrom, ledgerApply, the command key): every case of tests/fixtures/sidekick/hook-cases.json, and what the fixture cannot write. Pure Foundation.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-sidekick-ledger.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/SidekickText.swift $APP/SidekickExplain.swift $APP/SidekickLedger.swift \
    tests/CatTestSupport.swift tests/SidekickLedgerTests.swift \
    -o "$TEST_DIR/sidekick-ledger-tests"
"$TEST_DIR/sidekick-ledger-tests"
