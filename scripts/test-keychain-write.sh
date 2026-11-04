#!/usr/bin/env bash
# Keychain write in place: the app's Keychain.save updates the item that is there, adds one only when none is, and never deletes first.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-keychain-write.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    tests/CatTestSupport.swift NotchBuddy/Sources/App/KeychainWrite.swift tests/KeychainWriteTests.swift \
    -o "$TEST_DIR/keychain-write-tests"
"$TEST_DIR/keychain-write-tests"
