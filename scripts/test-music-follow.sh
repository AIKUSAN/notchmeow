#!/usr/bin/env bash
# The music pill's rules (MusicFollow): which of Apple Music and Spotify is shown, the scripts, the words.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-music-follow.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/MusicFollow.swift \
    tests/CatTestSupport.swift tests/MusicFollowTests.swift \
    -o "$TEST_DIR/music-follow-tests"
"$TEST_DIR/music-follow-tests"
