#!/usr/bin/env bash
# The music pill (MusicFollow and MusicController, GitHub build only): the source pins of the controller, the views, the catalog, the purpose line and the binary check.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-music-wiring.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

swiftc -swift-version 6 \
    tests/CatTestSupport.swift tests/MusicWiringTests.swift \
    -o "$TEST_DIR/music-wiring-tests"
"$TEST_DIR/music-wiring-tests"
