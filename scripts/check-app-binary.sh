#!/usr/bin/env bash
# Checks a built NotchMeow.app: FoundationModels weak-linked (the app must launch on macOS 15), and, for Release builds,
# the Debug-only AI base-URL override compiled out.
# `release` is the CI check: it also fails when FoundationModels isn't linked at all, which means the
# SDK had none and the Apple on-device provider was silently compiled out. It also fails when the Debug-only
# cat panel (CatDevPanel.swift, marked NM_CAT_DEV_PANEL) or the Debug-only Claude Code path override is in the binary, and
# when the Claude Code engine is missing (the Developer ID build ships it).
# `appstore` is for a build of the App Store target, even in its Debug configuration: no cat panel either, and no
# Claude Code engine, locator or plan card (the App Store build offers only the API-key path).
# `debug` is the other half of that proof: a Debug build must contain the cat panel, the engine and the override, so the
# checks above can fail.
# Usage: bash scripts/check-app-binary.sh path/to/NotchMeow.app [release|appstore|debug]
set -euo pipefail
APP="$1"
BINS=("$APP"/Contents/MacOS/NotchMeow*)   # Debug builds put the code in NotchMeow.debug.dylib
[ -e "${BINS[0]}" ] || { echo "No binary in $APP/Contents/MacOS" >&2; exit 1; }
STRINGS="$(mktemp "${TMPDIR:-/tmp}/nm-binary-strings.XXXXXX")"
trap 'rm -f "$STRINGS"' EXIT
weak=0
for BIN in "${BINS[@]}"; do
    if grep -q FoundationModels < <(otool -l "$BIN" | grep -A2 'LC_LOAD_DYLIB$'); then
        echo "✗ $(basename "$BIN") links FoundationModels strongly: NotchMeow would not launch on macOS 15" >&2
        exit 1
    fi
    if grep -q FoundationModels < <(otool -l "$BIN" | grep -A2 'LC_LOAD_WEAK_DYLIB'); then weak=1; fi
    strings "$BIN" >> "$STRINGS"
done
has() { grep -qF -- "$1" "$STRINGS"; }
# The desktop cat (sub-project H) is in every build, Debug, Release and App Store: its panel carries this marker.
if [ -n "${2:-}" ]; then
    has NM_DESKTOP_CAT_PANEL || { echo "✗ the desktop cat (NM_DESKTOP_CAT_PANEL) is missing from this build" >&2; exit 1; }
    echo "✓ The desktop cat is in this build"
    # The wardrobe (sub-project I) is in every build too: the painter and Settings' Wardrobe group carry this marker.
    has NM_WARDROBE_OUTFITS || { echo "✗ the wardrobe (NM_WARDROBE_OUTFITS) is missing from this build" >&2; exit 1; }
    echo "✓ The wardrobe is in this build"
fi
# The shelf (sub-project G1) is in every build, Debug, Release and App Store; its Debug panel is Debug-only.
if [ -n "${2:-}" ]; then
    has NM_SHELF_STORE_ACTIVE || { echo "✗ the shelf (NM_SHELF_STORE_ACTIVE) is missing from this build" >&2; exit 1; }
    echo "✓ The shelf is in this build"
fi
# The sidekick (sub-project F1) is in every build too: its app side carries this marker.
if [ -n "${2:-}" ]; then
    has NM_SIDEKICK_ENGINE_PRESENT || { echo "✗ the sidekick (NM_SIDEKICK_ENGINE_PRESENT) is missing from this build" >&2; exit 1; }
    echo "✓ The sidekick is in this build"
fi
# The link between machines (sub-project G2) is in every build too: Settings → Devices carries this marker. Its Debug-only fake peer (LinkDevPeer.swift) is not.
if [ -n "${2:-}" ]; then
    has NM_LINK_ENGINE_ACTIVE || { echo "✗ the link between machines (NM_LINK_ENGINE_ACTIVE) is missing from this build" >&2; exit 1; }
    echo "✓ The link between machines is in this build"
fi
# The Projects view (sub-project P-mac) is in every build too: ProjectsModel carries this marker.
if [ -n "${2:-}" ]; then
    has NM_PROJECTS_VIEW_ACTIVE || { echo "✗ the Projects view (NM_PROJECTS_VIEW_ACTIVE) is missing from this build" >&2; exit 1; }
    echo "✓ The Projects view is in this build"
fi
# The companion's store (sub-project F3a) is in every build too: Settings → Companion carries this marker.
if [ -n "${2:-}" ]; then
    has NM_COMPANION_STORE_ACTIVE || { echo "✗ the companion (NM_COMPANION_STORE_ACTIVE) is missing from this build" >&2; exit 1; }
    echo "✓ The companion is in this build"
fi
shelfpanel=0; has NM_SHELF_DEV_PANEL && shelfpanel=1
linkpeer=0; has NM_LINK_DEV_PEER && linkpeer=1
# The music pill (GitHub build only) follows Apple Music and Spotify: its controller carries this marker; its controller and Spotify's bundle ID are not in the App Store build.
music=0; has NM_MUSIC_FOLLOWS_SPOTIFY && music=1
spotify=0; has com.spotify.client && spotify=1
# A Debug build keeps the link's keys and device id under a Keychain service of its own; Release and App Store builds must not carry that name (and so can never write under it).
linkdebugsvc=0; has io.github.aikusan.notchmeow.debug && linkdebugsvc=1
panel=0; has NM_CAT_DEV_PANEL && panel=1
# The Desktop section of the cat panel (sub-project H) and its Wardrobe section (sub-project I) are Debug-only too.
devdesk=0; has NM_CAT_DEV_DESKTOP && devdesk=1
devward=0; has NM_CAT_DEV_WARDROBE && devward=1
override=0; has NM_CLAUDE_CODE_PATH_OVERRIDE && override=1
# What only the Claude Code engine has: its command line, the variable it strips, the plan card's note.
engine_missing=0
for text in "--include-partial-messages" "CLAUDE_CODE_OAUTH_TOKEN" "runs your installed Claude Code"; do
    has "$text" || engine_missing=$((engine_missing + 1))
done
# The Codex path override (F3a2-mac) is Debug-only, like the Claude one. What only the Codex engine has: a name it strips and two flags
# of its base command line. Markers are 16 bytes or more (CLAUDE.md): a shorter Swift literal is stored inline, where `strings` cannot see it.
codex_override=0; has NM_CODEX_PATH_OVERRIDE && codex_override=1
codex_missing=0
for text in "OPENAI_PROJECT_ID" "--ignore-user-config" "--skip-git-repo-check"; do
    has "$text" || codex_missing=$((codex_missing + 1))
done
if [ "${2:-}" = "release" ] && has NM_AI_BASE_URL_OVERRIDE; then
    echo "✗ this build still reads NM_AI_BASE_URL_OVERRIDE" >&2
    exit 1
fi
case "${2:-}" in
    release)
        [ "$panel" = 0 ] || { echo "✗ the Debug-only cat panel (NM_CAT_DEV_PANEL) is in this build" >&2; exit 1; }
        [ "$devdesk" = 0 ] || { echo "✗ the Debug-only Desktop section of the cat panel (NM_CAT_DEV_DESKTOP) is in this build" >&2; exit 1; }
        [ "$devward" = 0 ] || { echo "✗ the Debug-only Wardrobe section of the cat panel (NM_CAT_DEV_WARDROBE) is in this build" >&2; exit 1; }
        [ "$shelfpanel" = 0 ] || { echo "✗ the Debug-only shelf panel (NM_SHELF_DEV_PANEL) is in this build" >&2; exit 1; }
        [ "$linkpeer" = 0 ] || { echo "✗ the Debug-only link fake peer (NM_LINK_DEV_PEER) is in this build" >&2; exit 1; }
        [ "$linkdebugsvc" = 0 ] || { echo "✗ the Debug build's Keychain service name (io.github.aikusan.notchmeow.debug) is in this build" >&2; exit 1; }
        [ "$override" = 0 ] || { echo "✗ the Debug-only Claude Code path override (NM_CLAUDE_CODE_PATH_OVERRIDE) is in this build" >&2; exit 1; }
        [ "$engine_missing" = 0 ] || { echo "✗ the Claude Code engine is missing from this build" >&2; exit 1; }
        [ "$codex_override" = 0 ] || { echo "✗ the Debug-only Codex path override (NM_CODEX_PATH_OVERRIDE) is in this build" >&2; exit 1; }
        [ "$codex_missing" = 0 ] || { echo "✗ the Codex engine is missing from this build" >&2; exit 1; }
        [ "$music" = 1 ] && [ "$spotify" = 1 ] || { echo "✗ the music controller (NM_MUSIC_FOLLOWS_SPOTIFY) is missing from this build" >&2; exit 1; }
        echo "✓ No cat panel and no Claude Code override in this build; the Claude Code engine is in it, Codex engine in" ;;
    appstore)
        [ "$panel" = 0 ] || { echo "✗ the Debug-only cat panel (NM_CAT_DEV_PANEL) is in this build" >&2; exit 1; }
        [ "$devdesk" = 0 ] || { echo "✗ the Debug-only Desktop section of the cat panel (NM_CAT_DEV_DESKTOP) is in this build" >&2; exit 1; }
        [ "$devward" = 0 ] || { echo "✗ the Debug-only Wardrobe section of the cat panel (NM_CAT_DEV_WARDROBE) is in this build" >&2; exit 1; }
        [ "$shelfpanel" = 0 ] || { echo "✗ the Debug-only shelf panel (NM_SHELF_DEV_PANEL) is in this build" >&2; exit 1; }
        [ "$linkpeer" = 0 ] || { echo "✗ the Debug-only link fake peer (NM_LINK_DEV_PEER) is in this build" >&2; exit 1; }
        [ "$linkdebugsvc" = 0 ] || { echo "✗ the Debug build's Keychain service name (io.github.aikusan.notchmeow.debug) is in this build" >&2; exit 1; }
        [ "$override" = 0 ] || { echo "✗ the Debug-only Claude Code path override is in this build" >&2; exit 1; }
        [ "$engine_missing" = 3 ] || { echo "✗ part of the Claude Code engine (its command line, environment or plan card) is in the App Store build" >&2; exit 1; }
        [ "$codex_override" = 0 ] || { echo "✗ the Debug-only Codex path override (NM_CODEX_PATH_OVERRIDE) is in this build" >&2; exit 1; }
        [ "$codex_missing" = 3 ] || { echo "✗ part of the Codex engine is in the App Store build" >&2; exit 1; }
        [ "$music" = 0 ] && [ "$spotify" = 0 ] || { echo "✗ the music controller or Spotify's name is in the App Store build" >&2; exit 1; }
        echo "✓ No cat panel and no Claude Code engine in this build, no Codex engine" ;;
    debug)
        [ "$panel" = 1 ] || { echo "✗ the cat panel (NM_CAT_DEV_PANEL) is missing from this Debug build" >&2; exit 1; }
        [ "$devdesk" = 1 ] || { echo "✗ the cat panel's Desktop section (NM_CAT_DEV_DESKTOP) is missing from this Debug build" >&2; exit 1; }
        [ "$devward" = 1 ] || { echo "✗ the cat panel's Wardrobe section (NM_CAT_DEV_WARDROBE) is missing from this Debug build" >&2; exit 1; }
        [ "$shelfpanel" = 1 ] || { echo "✗ the shelf panel (NM_SHELF_DEV_PANEL) is missing from this Debug build" >&2; exit 1; }
        [ "$linkpeer" = 1 ] || { echo "✗ the link fake peer (NM_LINK_DEV_PEER) is missing from this Debug build" >&2; exit 1; }
        [ "$linkdebugsvc" = 1 ] || { echo "✗ the link's Debug Keychain service name is missing from this Debug build" >&2; exit 1; }
        [ "$override" = 1 ] || { echo "✗ the Claude Code path override (NM_CLAUDE_CODE_PATH_OVERRIDE) is missing from this Debug build" >&2; exit 1; }
        [ "$engine_missing" = 0 ] || { echo "✗ the Claude Code engine is missing from this Debug build" >&2; exit 1; }
        [ "$codex_override" = 1 ] || { echo "✗ the Codex path override (NM_CODEX_PATH_OVERRIDE) is missing from this Debug build" >&2; exit 1; }
        [ "$codex_missing" = 0 ] || { echo "✗ the Codex engine is missing from this Debug build" >&2; exit 1; }
        [ "$music" = 1 ] && [ "$spotify" = 1 ] || { echo "✗ the music controller (NM_MUSIC_FOLLOWS_SPOTIFY) is missing from this build" >&2; exit 1; }
        echo "✓ The cat panel, the Claude Code engine and its override are in this Debug build, Codex engine in" ;;
    "")
        # No mode argument provided: just run the shared checks (FoundationModels)
        ;;
    *)
        echo "unknown mode: ${2} (expected release, appstore or debug)" >&2
        exit 2
        ;;
esac
if [ "$weak" = 1 ]; then
    echo "✓ FoundationModels is weak-linked"
elif [ "${2:-}" = "release" ]; then
    echo "✗ FoundationModels is not linked at all: the Apple on-device provider was compiled out. Build with Xcode 26 or later (scripts/check-sdk.sh)." >&2
    exit 1
else
    echo "· FoundationModels not linked (this SDK has none: Apple on-device is compiled out)"
fi
[ "${2:-}" = "release" ] && echo "✓ No AI base-URL override in this Release build"
exit 0
