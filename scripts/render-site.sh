#!/usr/bin/env bash
# Redraws every picture of the site into docs/assets/img/ at 2x, from the render scripts, without launching NotchMeow. Run it at each tester round's cut and commit the PNGs.
#   bash scripts/render-site.sh
# It needs a Mac with a Retina screen: the Settings and plan card scripts draw at the screen's scale, and this script stops if a picture is not at 2x.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=docs/assets/img
TMP="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-render-site.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

# The pixel width of a PNG, to prove it is at 2x.
width() { sips -g pixelWidth "$1" | awk '/pixelWidth/ { print $2 }'; }
expect() { local w; w="$(width "$1")"; [ "$w" = "$2" ] || { echo "✗ $1 is $w px wide, expected $2: is this a Retina screen?" >&2; exit 1; }; echo "✓ $1 ($w px wide)"; }

# The island with agent sessions: the compact strip and the expanded overview, in the three display modes.
bash scripts/render-cats.sh --island --scale 2 --out "$OUT/island.png"
# Subagent kittens: three steps of a subagent's life (it arrives, one waits on an approval, one leaves).
bash scripts/render-cats.sh --kittens --scenario life --mode one --steps 3,7,9 --scale 2 --out "$OUT/kittens.png"
# The coats: every coat at the sizes of the island, with a kitten of each. The cells end at 966 px and a line marks the sheet's edge at 1062 px: sips cuts the sheet to 983 px (a 16 px gutter) so the page's box fills with the coats. The offset is 1 (not 0): sips centres a crop whose offsets are both 0.
bash scripts/render-cats.sh --sizes 20,66 --scale 2 --out "$TMP/coats.png"
H="$(sips -g pixelHeight "$TMP/coats.png" | awk '/pixelHeight/ { print $2 }')"
sips -c "$H" 983 --cropOffset 0 1 "$TMP/coats.png" --out "$OUT/coats.png" > /dev/null
# How the cats react: the eight states the site's buttons set, on one coat, each under the words of its button.
bash scripts/render-cats.sh --reactions --cats shrimpy --scale 2 --out "$OUT/reactions.png"
# An approval from the notch: the card of the island and the big cat.
bash scripts/render-approval-card.sh --scale 2 --out "$OUT/approval-card.png"
# The three display modes: Settings → Cat → Display, cut to the Display box (one height for each mode: the box is as high as its text).
bash scripts/render-cat-settings.sh --mode one --character shrimpy --height 170 --out "$OUT/mode-one.png"
bash scripts/render-cat-settings.sh --mode perAgent --character shrimpy --height 198 --out "$OUT/mode-per-agent.png"
bash scripts/render-cat-settings.sh --mode two --character shrimpy --height 183 --out "$OUT/mode-two.png"
# The Claude plan card. Its gauge sits right of the card's middle, and the card's red edge is at x 642 px: the picture is cut round the gauge (x 190 to 641, y 0 to 150) and padded with the card's own colour back to 640 x 196, so the gauge is centred in it.
bash scripts/render-plan-card.sh --out "$TMP/plan-card.png"
sips -c 151 452 --cropOffset 0 190 "$TMP/plan-card.png" --out "$TMP/plan-card-cut.png" > /dev/null
sips -p 196 640 --padColor 25262B "$TMP/plan-card-cut.png" --out "$OUT/plan-card.png" > /dev/null
# The app icon, for the page's header and tab.
cp NotchBuddy/Assets.xcassets/AppIcon.appiconset/icon_128x128.png "$OUT/icon.png"

expect "$OUT/mode-one.png" 1040
expect "$OUT/plan-card.png" 640
expect "$OUT/approval-card.png" 1344
expect "$OUT/reactions.png" 3056
echo "wrote $(ls "$OUT" | wc -l | tr -d ' ') pictures to $OUT"
