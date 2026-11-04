#!/usr/bin/env bash
# Settings → Agents: the words that tell the user what "Confirm & write" did (HookInstallNote.swift, pure) and pins on the app's source: the result lands right under the buttons of its box, a confirm reports the
# backup the writer returned and never a success it did not return, and the Plan usage switch is on only when the gauge is. Nothing reads or writes the real ~/.claude.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-hook-install-note.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"                 # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/HookInstallNote.swift \
    tests/CatTestSupport.swift tests/HookInstallNoteTests.swift \
    -o "$TEST_DIR/hook-install-note-tests"
"$TEST_DIR/hook-install-note-tests"
