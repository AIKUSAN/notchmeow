#!/usr/bin/env bash
# Companion files and the conversation store (F3a-mac, Task 3): owner-only folders and files, atomic writes, a link or a file over 8 MiB refused and left
# alone, the 50 kept, the three companion.* defaults through CompanionDefaults, and no message or path in the defaults. Works in a temp root only:
# never UserDefaults.standard, ~/Library or the shared store. Pure Foundation and POSIX.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-companion-store.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
export NM_COMPANION_TEST_ROOT="$TEST_DIR/root"

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CompanionText.swift $APP/CompanionRecords.swift $APP/CompanionFiles.swift $APP/CompanionStore.swift \
    $APP/ProjectsRules.swift $APP/ProjectsRegistry.swift \
    tests/CatTestSupport.swift tests/CompanionStoreTests.swift \
    -o "$TEST_DIR/companion-store-tests"
"$TEST_DIR/companion-store-tests"
