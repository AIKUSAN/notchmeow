#!/usr/bin/env bash
# The OpenAI plan's wiring (F3a2-mac): what the app wires together from the pure parts (the provider the factory makes, the words and
# button a Codex failure shows), plus the source pins no test program can run: the App Store exclusion, the one Debug-only path override,
# who may run a Codex turn, where the status is asked and the note's button. Never runs a real codex. Built with -D DEBUG, as a Debug build is.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-codex-wiring.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
swiftc -swift-version 6 -D DEBUG \
    NotchBuddy/Sources/App/AI/Core/*.swift \
    NotchBuddy/Sources/App/AppLog.swift \
    tests/AITestSupport.swift tests/CodexWiringTests.swift \
    -o "$TEST_DIR/CodexWiringTests"
"$TEST_DIR/CodexWiringTests"
