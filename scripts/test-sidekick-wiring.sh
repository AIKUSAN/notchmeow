#!/usr/bin/env bash
# Sidekick wiring: where HookServer, the approval card, the island, the chat, the drop and the settings call the sidekick's pure rules, pinned as source text.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-sidekick-wiring.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    tests/CatTestSupport.swift tests/SidekickWiringTests.swift \
    -o "$TEST_DIR/sidekick-wiring-tests"
"$TEST_DIR/sidekick-wiring-tests"
