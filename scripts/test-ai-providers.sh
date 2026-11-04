#!/usr/bin/env bash
# AI providers against tests/fake_local_llm.py: request bodies, streaming, failure modes.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-ai-providers.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
# -D DEBUG: the Debug-only base-URL override is under test too.
swiftc -swift-version 6 -D DEBUG \
    NotchBuddy/Sources/App/AI/Core/*.swift \
    NotchBuddy/Sources/App/AppLog.swift \
    tests/AITestSupport.swift tests/AIProviderTests.swift \
    -o "$TEST_DIR/ai-provider-tests"
"$TEST_DIR/ai-provider-tests"
