#!/usr/bin/env bash
# Hook routing, wiring: where HookServer, ApprovalInfo, AppState and the Claude Code pill's tap call the pure rules (HookOrigin), pinned as source text.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-hook-origin-wiring.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    tests/CatTestSupport.swift tests/HookOriginWiringTests.swift \
    -o "$TEST_DIR/hook-origin-wiring-tests"
"$TEST_DIR/hook-origin-wiring-tests"
