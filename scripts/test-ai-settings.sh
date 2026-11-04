#!/usr/bin/env bash
# AI settings: migration of the pre-E1 chat settings and the provider factory
# (which provider, URL and key each choice gets, Debug override included).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-ai-settings.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
swiftc -swift-version 6 \
    NotchBuddy/Sources/App/AI/Core/*.swift \
    NotchBuddy/Sources/App/AppLog.swift \
    tests/AITestSupport.swift tests/AISettingsTests.swift \
    -o "$TEST_DIR/ai-settings-tests"
"$TEST_DIR/ai-settings-tests"
