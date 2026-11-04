#!/usr/bin/env bash
# The Codex engine against the shared fixtures in tests/fixtures/ai/codex/ and the fake codex there: the command line,
# the environment, the prompt and the folders. Never runs a real codex. One test program per tests/Codex*Tests.swift,
# built with -D DEBUG as a Debug build is.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-codex-plan.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
for test in tests/Codex*Tests.swift; do
    [ "$(basename "$test")" = CodexWiringTests.swift ] && continue
    name="$(basename "$test" .swift)"
    swiftc -swift-version 6 -D DEBUG \
        NotchBuddy/Sources/App/AI/Core/*.swift \
        NotchBuddy/Sources/App/AppLog.swift \
        tests/AITestSupport.swift "$test" \
        -o "$TEST_DIR/$name"
    echo "== $name"
    "$TEST_DIR/$name"
done
