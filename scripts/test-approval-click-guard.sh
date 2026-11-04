#!/usr/bin/env bash
# The permission card's 600 ms click guard: the pure rule (ApprovalClickGuard.swift). Its call sites in ApprovalView are pinned by scripts/test-u1-wiring.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-approval-guard.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 NotchBuddy/Sources/App/ApprovalClickGuard.swift tests/ApprovalClickGuardTests.swift -o "$TEST_DIR/approval-guard-tests"
"$TEST_DIR/approval-guard-tests"
