#!/usr/bin/env bash
# AI core: the three SSE parsers against every recorded stream in tests/fixtures/ai/sse/.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-ai-stream.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
swiftc -swift-version 6 \
    NotchBuddy/Sources/App/AI/Core/*.swift \
    NotchBuddy/Sources/App/AppLog.swift \
    tests/AITestSupport.swift tests/AIStreamTests.swift \
    -o "$TEST_DIR/ai-stream-tests"
"$TEST_DIR/ai-stream-tests"
