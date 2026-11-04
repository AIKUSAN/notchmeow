#!/usr/bin/env bash
# The words of the session view's step rows (moved out of HookServer, unchanged).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-session-steps.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 NotchBuddy/Sources/App/SessionStepText.swift tests/SessionStepTextTests.swift -o "$TEST_DIR/session-step-tests"
"$TEST_DIR/session-step-tests"
