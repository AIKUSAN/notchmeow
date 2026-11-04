#!/usr/bin/env bash
# The link's pairing rules (LinkPairing.swift: commitment, code, clocks, the responder's and the initiator's machines): every case of tests/fixtures/link/pairing-cases.json.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-link-pairing.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/LinkBytes.swift $APP/LinkName.swift $APP/LinkFrames.swift $APP/LinkPairing.swift \
    tests/CatTestSupport.swift tests/LinkPairingTests.swift \
    -o "$TEST_DIR/link-pairing-tests"
"$TEST_DIR/link-pairing-tests"
