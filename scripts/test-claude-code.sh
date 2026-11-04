#!/usr/bin/env bash
# The Claude Code engine against the shared fixtures in tests/fixtures/ai/claude-code/ and the fake `claude` there:
# the command line, the environment, the transcript parser, the runner, the locator and the chat's session.
# Never runs a real claude. One test program per tests/ClaudeCode*Tests.swift, built with -D DEBUG as a Debug build is
# (the Debug-only path override is tested; Release and App Store builds compile it out, which check-app-binary.sh proves).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-claude-code.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
for test in tests/ClaudeCode*Tests.swift; do
    name="$(basename "$test" .swift)"
    swiftc -swift-version 6 -D DEBUG \
        NotchBuddy/Sources/App/AI/Core/*.swift \
        NotchBuddy/Sources/App/AppLog.swift \
        tests/AITestSupport.swift "$test" \
        -o "$TEST_DIR/$name"
    echo "== $name"
    "$TEST_DIR/$name"
done
