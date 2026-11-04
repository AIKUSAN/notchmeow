#!/usr/bin/env bash
# Wardrobe drawing (sub-project I): every colour role is a colour, only the big-cat role wears an outfit (never a small cat or a kitten, whatever the diameter), the fade, and all 16 outfits
# on all 16 coats drawn big at Ø64 and at the compact notch's Ø20 (each changes the picture, none reaches above the strip), drawn into bitmaps by the real CatRenderer.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-wardrobe-draw.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/Wardrobe.swift $APP/CatOutfit.swift $APP/CatOutfitDraw.swift $APP/CatRenderer.swift \
    tests/CatTestSupport.swift tests/CatBitmapSupport.swift tests/WardrobeDrawTests.swift \
    -o "$TEST_DIR/wardrobe-draw-tests"
"$TEST_DIR/wardrobe-draw-tests"
