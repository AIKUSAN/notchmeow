#!/usr/bin/env bash
# AI attachments: every case in attachment-cases.json (files generated, never committed),
# the per-provider plan of spec §3, and the HTML tag strip. Uses PDFKit, Vision and AppKit.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-ai-attachments.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
python3 tests/fixtures/ai/make_attachments.py "$TEST_DIR/files"
swiftc -swift-version 6 \
    NotchBuddy/Sources/App/AI/Core/*.swift \
    NotchBuddy/Sources/App/AI/Platform/AttachmentExtractor.swift \
    NotchBuddy/Sources/App/AppLog.swift \
    tests/AITestSupport.swift tests/AIAttachmentTests.swift \
    -o "$TEST_DIR/ai-attachment-tests"
"$TEST_DIR/ai-attachment-tests" "$TEST_DIR/files"
