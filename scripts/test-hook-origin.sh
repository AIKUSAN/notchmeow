#!/usr/bin/env bash
# Which pill a hook event belongs to (HookOrigin): VS Code and every terminal reach the Claude Code pill, Cursor, Codex and tagged agents keep theirs, the notes name
# the app the user is in. Pure Foundation; nothing here launches or touches NotchMeow.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-hook-origin.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/HookOrigin.swift \
    tests/CatTestSupport.swift tests/HookOriginTests.swift \
    -o "$TEST_DIR/hook-origin-tests"
"$TEST_DIR/hook-origin-tests"
