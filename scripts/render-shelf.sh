#!/usr/bin/env bash
# Draws the shelf's pictures (sub-project G1) without launching NotchMeow, and runs the checks that need pixels (see scripts/render-shelf.swift).
#   bash scripts/render-shelf.sh --drop --out DIR      the two drop halves, with the pointer over each
#   bash scripts/render-shelf.sh --view --out DIR      the shelf view: empty, with files, and full
#   bash scripts/render-shelf.sh --badge --out DIR     the compact island with the badge: at rest, and with the pointer over the wing
#   bash scripts/render-shelf.sh --panel --out DIR     the Debug-only shelf panel
#   bash scripts/render-shelf.sh --ask-check           the Ask half is untouched: the layer draws nothing left of the centre line
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-render-shelf.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
export NM_LOG_DIR="$BUILD_DIR/logs"   # nothing here writes a log, but nothing may write into ~/Library/Logs either
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 -D DEBUG \
    $APP/ShelfRules.swift $APP/ShelfDrop.swift $APP/ShelfDropLayer.swift $APP/ShelfStore.swift $APP/ShelfModel.swift $APP/ShelfDragOut.swift $APP/ShelfContent.swift $APP/ShelfBadge.swift $APP/ShelfBadgeView.swift $APP/ShelfDevModel.swift $APP/ShelfDevPanel.swift \
    scripts/render-shelf.swift \
    -o "$BUILD_DIR/render-shelf"
"$BUILD_DIR/render-shelf" "$@"
