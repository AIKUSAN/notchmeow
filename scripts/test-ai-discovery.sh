#!/usr/bin/env bash
# AI discovery: identification rules, fake server personas, and the 400 ms budget
# when nothing is running (all probes in parallel, 0.3 s each).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-ai-discovery.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
swiftc -swift-version 6 \
    NotchBuddy/Sources/App/AI/Core/*.swift \
    NotchBuddy/Sources/App/AppLog.swift \
    tests/AITestSupport.swift tests/AIDiscoveryTests.swift \
    -o "$TEST_DIR/ai-discovery-tests"
"$TEST_DIR/ai-discovery-tests"
