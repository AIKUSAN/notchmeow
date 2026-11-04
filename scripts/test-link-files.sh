#!/usr/bin/env bash
# The link's files (LinkFiles.swift): the sink (exclusive create, numbering, 0600 then 0644, quarantine, discard) and the source (what may be sent). A temp folder only.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-link-files.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/LinkBytes.swift $APP/LinkName.swift $APP/LinkFrames.swift $APP/LinkFiles.swift \
    tests/CatTestSupport.swift tests/LinkFilesTests.swift \
    -o "$TEST_DIR/link-files-tests"
"$TEST_DIR/link-files-tests"
