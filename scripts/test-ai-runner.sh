#!/usr/bin/env bash
# AI chat runner: conversation/per-turn files, error copy, fallback and countdown against
# the fake server, and the log leak test (a marker word must never reach a log line).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-ai-runner.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
swiftc -swift-version 6 \
    NotchBuddy/Sources/App/AI/Core/*.swift \
    NotchBuddy/Sources/App/AppLog.swift \
    tests/AITestSupport.swift tests/AIRunnerTests.swift \
    -o "$TEST_DIR/ai-runner-tests"
"$TEST_DIR/ai-runner-tests"
