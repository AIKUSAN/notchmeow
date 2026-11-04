#!/usr/bin/env bash
# Renders the cats into a PNG contact sheet with the real CatRenderer, without launching the app.
#   bash scripts/render-cats.sh --out cats.png [--cats shrimpy,momo] [--sizes 12,20,66] [--scale 2]
# The other modes (--stage, --states, --emotes, --mouths, --catch, --greeting, --bench) are listed at the top of scripts/render-cats.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-render-cats.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
APP=NotchBuddy/Sources/App
# RENDER_CATS_OPT=1 builds with -O (the frame-time number in a Release build); the default is a Debug build.
swiftc -swift-version 6 ${RENDER_CATS_OPT:+-O} \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/Wardrobe.swift $APP/CatOutfit.swift $APP/CatOutfitDraw.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift \
    $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift $APP/CatCast.swift $APP/CatAgentList.swift $APP/CatKittens.swift $APP/CatKittenHooks.swift $APP/CatKittenDraw.swift \
    $APP/CatIslandLayout.swift $APP/IslandWing.swift \
    $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/DesktopCatTrip.swift $APP/WardrobeAuto.swift $APP/DesktopCatLayout.swift $APP/DesktopCatInput.swift $APP/DesktopCatPacer.swift $APP/DesktopCatDraw.swift \
    scripts/render-cats.swift scripts/render-cats-desktop.swift scripts/render-cats-wing.swift scripts/render-cats-wardrobe.swift \
    -o "$BUILD_DIR/render-cats"
"$BUILD_DIR/render-cats" "$@"
