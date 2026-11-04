#!/usr/bin/env bash
# Apple's on-device provider only compiles with the macOS 26 SDK. On an older Xcode,
# `#if canImport(FoundationModels)` quietly compiles it out and the app would ship without it.
set -euo pipefail
SDK="$(xcrun --sdk macosx --show-sdk-path)"
VERSION="$(xcrun --sdk macosx --show-sdk-version)"
if [ ! -d "$SDK/System/Library/Frameworks/FoundationModels.framework" ]; then
    echo "✗ The active macOS SDK ($VERSION) has no FoundationModels: the Apple on-device provider would be compiled out." >&2
    echo "  Use Xcode 26 or later: pin the runner (runs-on: macos-26) or select it with xcode-select -s." >&2
    exit 1
fi
echo "✓ macOS SDK $VERSION has FoundationModels"
