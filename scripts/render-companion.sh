#!/usr/bin/env bash
# Draws the companion's chat pictures (F3a-mac, Task 10) without launching NotchMeow (see scripts/render-companion.swift): the chat in the island at 1, 6 and 12 messages
# (280, 480 and 560 pt), the chat in its own 520 × 640 window, the island's note while it is popped out, the saved conversations, a Fix result with its cut note, the
# Folder control for each level, the model picker with the Claude plan row, and a reply with the one-time cloud line.
#   bash scripts/render-companion.sh --out DIR [--scale 2]
# It compiles every file of the app but NotchBuddyApp.swift (about two minutes), and runs in a home folder of its own: scripts/render-home-guard.sh points Foundation at that
# folder and kills the tool if it opens the real ~/.claude, ~/.gemini or ~/.codex. The companion's store lives under that folder too (the tool stops if it would be anywhere
# else), and the sample conversations are saved there. The defaults are a domain of its own (render-companion), deleted when the script ends; the owner's preferences are never touched.
# What is read, stated plainly: the app's views read the Keychain on appear (PromptView.onAppear → AIService.prewarm → KeychainStore.shared loads the items of service
# io.github.aikusan.notchmeow, read-only), and if ImageRenderer fires ModelPickerView.onAppear it probes 127.0.0.1 local-model ports. Nothing from those reads is printed,
# drawn, sent or stored, and the pictures never carry a secret. This script itself reads $TMPDIR and $HOME, to make its folders and to clean up.
# Disclosed to the owner at checkpoint 1; render-settings already reads the Keychain by the same design.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-render-companion.XXXXXX")"
REAL_HOME="$HOME"
cleanup() {
    rm -rf "$BUILD_DIR"
    defaults delete render-companion > /dev/null 2>&1 || true
    rm -f "$REAL_HOME/Library/Preferences/render-companion.plist"
}
trap cleanup EXIT
export NM_LOG_DIR="$BUILD_DIR/logs"
mkdir -p "$BUILD_DIR/home"
APP=NotchBuddy/Sources/App
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(find "$APP" -name '*.swift' ! -name NotchBuddyApp.swift | sort)
swiftc -swift-version 6 -suppress-warnings "${FILES[@]}" scripts/render-companion.swift -o "$BUILD_DIR/render-companion"
. scripts/render-home-guard.sh
render_home_guard "$BUILD_DIR/home" "$BUILD_DIR/render-companion" --home "$BUILD_DIR/home" "$@"
