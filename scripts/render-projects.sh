#!/usr/bin/env bash
# Draws the Projects views (sub-project P-mac, Task 6) without launching NotchMeow (see scripts/render-projects.swift). The views are the app's own
# (NotchBuddy/Sources/App/ProjectsViews.swift); the data is the scenarios of tests/fixtures/mac/projects-scenarios.json replayed through the model.
#   bash scripts/render-projects.sh --island claude --out DIR     the island: the big card, the pill grid (--many: seven projects)
#   bash scripts/render-projects.sh --island collide --out DIR    two same-named projects with long parents: their pills draw the parent under the folder (checked)
#   bash scripts/render-projects.sh --island card --out DIR       the big card for a very long name: the name gives way, "· N sessions" stays whole (checked)
#   bash scripts/render-projects.sh --island agents --out DIR     the folded agents layout: the Claude Code card's chevron and count
#   bash scripts/render-projects.sh --island agents-open --out DIR  the 252 pt island with the expanded section
#   bash scripts/render-projects.sh --screen [--empty|--many] --out DIR  the Projects screen, 240 pt (--many: six projects of two sessions, which scrolls)
#   bash scripts/render-projects.sh --screen-check                the screen's checks, no pictures: top-aligned, clear of the cat, in a ScrollView that scrolls (exit 1 on one)
#   bash scripts/render-projects.sh --peek --out DIR              the peek over the left card
#   bash scripts/render-projects.sh --badge --out DIR             the compact strip with the waiting badge, at 32 and 24 pt
#   bash scripts/render-projects.sh --all --out DIR               every picture
#   bash scripts/render-projects.sh --text-check                  every string the views draw, checked for a path separator (exit 1 on one)
#   bash scripts/render-projects.sh --check                       every check, no pictures: the strings, the peek's frame and its lines, the screen (exit 1 on one)
#   bash scripts/render-projects.sh --frame-check                 the peek's frame and its "+N more" lines, no pictures (exit 1 on one)
#   bash scripts/render-projects.sh --reorder-check               the pill grid and the section hosted with [A, B, C] then [C, A, B]: each project's reported frame is where it is drawn (exit 1 on one)
# Run from anywhere: the script moves to the repository root, where the fixture is read.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-render-projects.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
export NM_LOG_DIR="$BUILD_DIR/logs"   # nothing here writes a log, but nothing may write into ~/Library/Logs either
APP=NotchBuddy/Sources/App
swiftc -swift-version 6 \
    $APP/CatMath.swift $APP/Theme.generated.swift $APP/CatPresets.swift $APP/CatGeometry.swift $APP/CatLook.swift $APP/CatDrawing.swift $APP/CatEffects.swift \
    $APP/CatFace.swift $APP/CatFur.swift $APP/CatSmallEye.swift $APP/CatOutfit.swift $APP/CatOutfitDraw.swift $APP/CatRenderer.swift $APP/Personality.swift $APP/CatRules.swift $APP/MotionProfiles.swift $APP/CatEngine.swift \
    $APP/CatSettings.swift $APP/CatDisplay.swift $APP/CatAgentCats.swift $APP/CatCast.swift $APP/CatAgentList.swift $APP/CatKittens.swift $APP/CatIslandLayout.swift $APP/DesktopCatSpots.swift $APP/DesktopCatSettings.swift $APP/Wardrobe.swift $APP/WardrobeSettings.swift $APP/WardrobeAuto.swift $APP/ProjectsRules.swift $APP/ProjectCatSettings.swift $APP/CatSettingsStore.swift \
    $APP/CatKittenDraw.swift $APP/ProjectsRegistry.swift $APP/ProjectsSnapshot.swift $APP/ProjectsLayout.swift $APP/ShelfBadge.swift $APP/ShelfBadgeView.swift \
    $APP/SessionStepText.swift $APP/ProjectsModel.swift $APP/ProjectsViews.swift \
    scripts/render-projects.swift \
    -o "$BUILD_DIR/render-projects"
"$BUILD_DIR/render-projects" "$@"
