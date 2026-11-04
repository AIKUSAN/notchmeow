#!/usr/bin/env bash
# The Network.framework transport (LinkNetwork.swift) over real TCP on 127.0.0.1: records, a record of length 0, and a pairing through a LinkListener without an advert (no Bonjour, no prompt).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-link-network.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/LinkBytes.swift $APP/LinkName.swift $APP/LinkFrames.swift $APP/LinkNoise.swift $APP/LinkPairing.swift $APP/LinkFlow.swift $APP/LinkFiles.swift \
    $APP/LinkKeychain.swift $APP/LinkChannel.swift $APP/LinkPairRun.swift $APP/LinkTransferRun.swift $APP/LinkNetwork.swift \
    tests/CatTestSupport.swift tests/LinkNetworkTests.swift \
    -o "$TEST_DIR/link-network-tests"
"$TEST_DIR/link-network-tests"
