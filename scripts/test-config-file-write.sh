#!/usr/bin/env bash
# ConfigFileWrite: writing an agent's config file through a symbolic link (the link stays, the file it points at changes, its permissions are kept, the dated backup is a copy), all in a
# temp folder of this script's own, and the source pins that the app's writers use it. Nothing reads or writes the real ~/.claude, ~/.gemini or ~/.codex.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-config-write.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"                 # tests never write to ~/Library/Logs
export NM_CONFIG_TEST_DIR="$TEST_DIR/files"        # every config file of the test lives here

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/ConfigFileWrite.swift \
    tests/CatTestSupport.swift tests/ConfigFileWriteTests.swift \
    -o "$TEST_DIR/config-file-write-tests"
"$TEST_DIR/config-file-write-tests"
