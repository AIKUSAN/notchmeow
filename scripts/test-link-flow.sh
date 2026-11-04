#!/usr/bin/env bash
# What each side of a transfer does with each frame (LinkFlow.swift): every case of tests/fixtures/link/flow-cases.json, and a seeded fuzz. Foundation only.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-link-flow.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/LinkBytes.swift $APP/LinkName.swift $APP/LinkFrames.swift $APP/LinkFlow.swift $APP/LinkCardRules.swift \
    tests/CatTestSupport.swift tests/LinkFlowTests.swift \
    -o "$TEST_DIR/link-flow-tests"
"$TEST_DIR/link-flow-tests"
# The contract's first-frame limit (flow-cases.json: firstFrameMs) is the real constant of the receiving run.
grep -q 'static let firstFrameMs = 10_000' $APP/LinkTransferRun.swift || { echo "✗ LinkTransferReceive.firstFrameMs is not 10_000 any more: docs/LINK-CONTRACT.md and flow-cases.json say 10 s"; exit 1; }
echo "✓ LinkTransferReceive.firstFrameMs is 10_000, as the contract says"
