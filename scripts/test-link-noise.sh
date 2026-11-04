#!/usr/bin/env bash
# The link's Noise layer (LinkNoise.swift, on CryptoKit): every vector and damaged-message case of tests/fixtures/link/noise-vectors.json. Foundation and CryptoKit only.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-link-noise.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/LinkNoise.swift \
    tests/CatTestSupport.swift tests/LinkNoiseTests.swift \
    -o "$TEST_DIR/link-noise-tests"
"$TEST_DIR/link-noise-tests"
