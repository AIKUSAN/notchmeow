#!/usr/bin/env bash
# Draws the Claude plan card into a PNG without launching NotchMeow (see scripts/render-plan-card.swift).
#   bash scripts/render-plan-card.sh --out plan-card.png [--stacked] [--shift 34] [--waiting] [--ago 5]
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-render-plan-card.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
export NM_LOG_DIR="$BUILD_DIR/logs"
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/Personality.swift $APP/CatRules.swift $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift \
    $APP/CatCast.swift $APP/CatAgentList.swift $APP/CatKittens.swift $APP/CatIslandLayout.swift $APP/ClaudePlanGauge.swift $APP/ClaudePlanCardView.swift \
    scripts/render-plan-card.swift \
    -o "$BUILD_DIR/render-plan-card"
"$BUILD_DIR/render-plan-card" "$@"
