#!/usr/bin/env bash
# Companion wiring (F3a-mac, Task 4): where ClaudeService reads the companion's turn and records what it sent, the Claude Code preamble inside the App
# Store exclusion, Companion's reads of the Projects model, and that the turn logs nothing and starts no timer. E3's engine and fixtures must not change.
set -euo pipefail
cd "$(dirname "$0")/.."
# E3_HASH pins the content of the guarded paths (E3's Mac engine and the AI fixtures): a hash of their tracked files, so a squash or a rebase merge
# or a shallow clone cannot make the check vanish. A deliberate E3 change bumps E3_HASH in the same commit; any other change fails here.
E3_HASH=708b133672261450a78668990631d729d5290f5a3adee4653374aff5626f737f
# The sibling brains' fixtures (Codex, OpenCode, the recording scrubber) live beside E3's under tests/fixtures/ai but are not E3's.
E3_PATHS=(NotchBuddy/Sources/App/AI/Core/ClaudeCodeEngine.swift tests/fixtures/ai ':!tests/fixtures/ai/codex' ':!tests/fixtures/ai/opencode' ':!tests/fixtures/ai/scrub_recording.py')
e3_now="$(git ls-files -z -- "${E3_PATHS[@]}" | xargs -0 shasum -a 256 | shasum -a 256 | cut -d' ' -f1)"
if [ "$e3_now" != "$E3_HASH" ]; then
    echo "✗ E3's engine or the AI fixtures changed: their content hash is now $e3_now (pinned $E3_HASH)." >&2
    echo "  Bump E3_HASH in the same commit as a deliberate E3 change." >&2
    exit 1
fi
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-companion-wiring.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    tests/CatTestSupport.swift tests/CompanionWiringTests.swift \
    -o "$TEST_DIR/companion-wiring-tests"
"$TEST_DIR/companion-wiring-tests"
