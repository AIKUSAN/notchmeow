#!/usr/bin/env bash
# The link's conversations (LinkPairRun, LinkTransferReceive, LinkTransferSend over LinkChannel) between two in-memory ends: pairing and transfer, end to end. No socket, no Keychain, no network.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-link-session.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/LinkBytes.swift $APP/LinkName.swift $APP/LinkFrames.swift $APP/LinkNoise.swift $APP/LinkPairing.swift $APP/LinkFlow.swift $APP/LinkFiles.swift \
    $APP/LinkKeychain.swift $APP/LinkChannel.swift $APP/LinkPairRun.swift $APP/LinkTransferRun.swift \
    tests/CatTestSupport.swift tests/LinkSessionTests.swift \
    -o "$TEST_DIR/link-session-tests"
"$TEST_DIR/link-session-tests"
