#!/usr/bin/env bash
# Draws NotchMeow's icons (app icon, menu-bar template, Windows and Linux icons) with the real CatRenderer, without launching the app.
#   bash scripts/gen-icons.sh              rewrites the 18 files in place
#   bash scripts/gen-icons.sh <outDir>     writes the same tree under <outDir>
# The drawing is in scripts/gen-icons.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-gen-icons.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 -O \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/Wardrobe.swift $APP/CatOutfit.swift $APP/CatOutfitDraw.swift $APP/CatRenderer.swift \
    $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatGreeting.swift $APP/CatGreetingRenderer.swift \
    scripts/gen-icons.swift \
    -o "$BUILD_DIR/gen-icons"
"$BUILD_DIR/gen-icons" "$@"
