#!/usr/bin/env bash
# The rules behind the link's one island card (LinkCardRules): another flow never replaces a card the user is about to click, a flow ends only its own card, and a click is ignored for 700 ms after
# the card changes kind and for a card that is no longer the one shown. Foundation only: no network, no Keychain, no clock.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-link-service.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/LinkCardRules.swift \
    tests/CatTestSupport.swift tests/LinkServiceTests.swift \
    -o "$TEST_DIR/link-service-tests"
"$TEST_DIR/link-service-tests"
