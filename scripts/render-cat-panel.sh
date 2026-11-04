#!/usr/bin/env bash
# Draws the Debug-only cat panel into a PNG without launching NotchMeow (see scripts/render-cat-panel.swift).
#   bash scripts/render-cat-panel.sh --out panel.png [--height 2200]
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-render-panel.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
export NM_LOG_DIR="$BUILD_DIR/logs"   # the readout writes a log line: never into ~/Library/Logs
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 -D DEBUG \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/Wardrobe.swift $APP/CatOutfit.swift $APP/CatOutfitDraw.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/AppLog.swift $APP/CatFrameMeter.swift $APP/CatFrameReadout.swift $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift \
    $APP/CatFileRule.swift $APP/AI/Core/Attachments.swift $APP/AI/Core/AICatalog.swift $APP/AI/Core/ModelProvider.swift $APP/AI/Core/ContextBudget.swift \
    $APP/CatDevModel.swift $APP/CatDevPanel.swift \
    $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatKittens.swift $APP/CatKittenDraw.swift $APP/CatIslandLayout.swift \
    $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/DesktopCatTrip.swift $APP/DesktopCatPacer.swift $APP/DesktopCatDraw.swift $APP/DesktopCatDevModel.swift $APP/DesktopCatDevPanel.swift $APP/WardrobeAuto.swift $APP/WardrobePreviewViews.swift $APP/WardrobeDevPanel.swift \
    scripts/render-cat-panel.swift \
    -o "$BUILD_DIR/render-cat-panel"
"$BUILD_DIR/render-cat-panel" "$@"
