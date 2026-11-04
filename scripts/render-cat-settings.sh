#!/usr/bin/env bash
# Draws Settings → Cat into a PNG without launching NotchMeow (see scripts/render-cat-settings.swift).
#   bash scripts/render-cat-settings.sh --out settings.png [--height 1500] [--width 520] [--character momo] [--preset chill] [--fur] [--collar band]
#                                       [--mode one|perAgent|two] [--pair momo,latte] [--agents]
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-render-settings.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
export NM_LOG_DIR="$BUILD_DIR/logs"
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/CatOutfit.swift $APP/CatOutfitDraw.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift $APP/CatCast.swift $APP/CatAgentList.swift $APP/CatKittens.swift $APP/CatIslandLayout.swift $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/Wardrobe.swift $APP/WardrobeSettings.swift $APP/WardrobeAuto.swift $APP/ProjectsRules.swift $APP/ProjectCatSettings.swift $APP/ProjectsLayout.swift $APP/CatSettingsStore.swift $APP/SettingsRoute.swift $APP/SettingsLayout.swift $APP/SettingsStatus.swift $APP/SettingsColors.swift $APP/SettingsCard.swift $APP/SettingRow.swift $APP/SwitchRow.swift $APP/StatusChip.swift $APP/WrapRow.swift $APP/HelpText.swift $APP/CatDisplayPreview.swift $APP/WardrobePreviewViews.swift $APP/WardrobeSettingsView.swift $APP/CatSettingsView.swift \
    scripts/render-cat-settings.swift \
    -o "$BUILD_DIR/render-cat-settings"
"$BUILD_DIR/render-cat-settings" "$@"
