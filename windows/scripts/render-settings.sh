#!/usr/bin/env bash
# Draws the Settings window's pictures for the owner's checkpoint (Settings restyle, Task 5): each place at each width, cut from the dev server's sample frame. Each width
# renders inside an iframe of its own width (settings.html?shot=<W>) in a headless window of that width: the frame's real width is read back from the page and must equal W,
# and the picture is cropped to W x H. Not part of CI. It writes to --out, to a throwaway Chrome profile and Vite's log (a mktemp folder, moved to the Trash with `trash`
# at exit), and to Vite's own dependency cache under windows/node_modules/.vite (not removed). It stops the Vite server it started.
#
# usage: render-settings.sh [--out DIR] [--state ready|empty|error] [--stress] [--page P] [--tab T] [--width W] [--height H] [--theme dark|light|both]
set -euo pipefail

usage() {
  echo "usage: render-settings.sh [--out DIR] [--state ready|empty|error] [--stress] [--page P] [--tab T] [--width W] [--height H] [--theme dark|light|both]" >&2
  exit 2
}

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${TMPDIR:-/tmp}/settings-tauri"
STATE="ready"
STRESS=""
PAGE=""
TAB=""
WIDTHS="415 720 1100"
HEIGHT="2400"
THEMES="dark light"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
PORT="1421"

while [ $# -gt 0 ]; do
  case "$1" in
    --out) [ $# -ge 2 ] || usage; OUT="$2"; shift 2 ;;
    --state) [ $# -ge 2 ] || usage; STATE="$2"; shift 2 ;;
    --stress) STRESS="1"; shift ;;
    --page) [ $# -ge 2 ] || usage; PAGE="$2"; shift 2 ;;
    --tab) [ $# -ge 2 ] || usage; TAB="$2"; shift 2 ;;
    --width) [ $# -ge 2 ] || usage; WIDTHS="$2"; shift 2 ;;
    --height) [ $# -ge 2 ] || usage; HEIGHT="$2"; shift 2 ;;
    --theme) [ $# -ge 2 ] || usage; case "$2" in dark) THEMES="dark" ;; light) THEMES="light" ;; both) THEMES="dark light" ;; *) usage ;; esac; shift 2 ;;
    *) usage ;;
  esac
done

case "$STATE" in ready|empty|error) ;; *) usage ;; esac
case "$HEIGHT" in ''|*[!0-9]*) usage ;; esac
for w in $WIDTHS; do case "$w" in ''|*[!0-9]*) usage ;; esac; done
[ -z "$TAB" ] || [ -n "$PAGE" ] || usage

# The places: the pages the owner asked for, or all of them (each chat and cat tab too).
if [ -n "$PAGE" ]; then
  PLACES="$PAGE${TAB:+/$TAB}"
else
  PLACES="general agents chat/yourai chat/keys chat/localmodels chat/sidekick services cat/look cat/outfits cat/personality cat/agentcats devices"
fi

[ -x "$CHROME" ] || { echo "Chrome not found: $CHROME" >&2; exit 1; }

mkdir -p "$OUT"
PROFILE="$(mktemp -d "${TMPDIR:-/tmp}/settings-chrome.XXXXXX")"
LOG="$PROFILE/vite.log"
CHROME_LOG="$PROFILE/chrome.log"

# A failed run says what it was and shows the last lines of Chrome's log (its stderr).
fail_run() {
  echo "$1" >&2
  tail -5 "$CHROME_LOG" >&2
  exit 1
}
SERVER=""

cleanup() {
  if [ -n "$SERVER" ]; then
    pkill -P "$SERVER" 2>/dev/null || true
    kill "$SERVER" 2>/dev/null || true
  fi
  if command -v trash >/dev/null 2>&1; then
    trash "$PROFILE" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if curl -s -o /dev/null "http://127.0.0.1:$PORT/settings.html"; then
  echo "port $PORT is already in use: stop the server on it first" >&2
  exit 1
fi

cd "$ROOT"
npx --no-install vite --port "$PORT" --strictPort --host 127.0.0.1 >"$LOG" 2>&1 &
SERVER=$!

ready=""
for _ in $(seq 1 60); do
  if curl -s -o /dev/null "http://127.0.0.1:$PORT/settings.html"; then
    ready="1"
    break
  fi
  sleep 0.5
done
if [ -z "$ready" ]; then
  echo "the Vite server did not start on port $PORT; its log:" >&2
  tail -20 "$LOG" >&2
  exit 1
fi

# One headless Chrome run: the same flags for the width read and for the picture.
chrome() {
  local win_w="$1"; shift
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --no-first-run --disable-extensions \
    --user-data-dir="$PROFILE" --window-size="$win_w,$HEIGHT" --virtual-time-budget=5000 "$@" 2>>"$CHROME_LOG"
}

count=0
for place in $PLACES; do
  page="${place%%/*}"
  tab=""
  case "$place" in */*) tab="${place#*/}" ;; esac
  for w in $WIDTHS; do
    win_w="$w"
    for theme in $THEMES; do
      url="http://127.0.0.1:$PORT/settings.html?shot=$w&h=$HEIGHT&sample=$STATE&page=$page"
      [ -z "$tab" ] || url="$url&tab=$tab"
      [ -z "$STRESS" ] || url="$url&stress"
      url="$url&theme=$theme"

      dom="$(chrome "$win_w" --dump-dom "$url" || true)"
      if ! grep -q "id=\"frame-width\">" <<<"$dom"; then
        dom="$(chrome "$win_w" --dump-dom "$url" || true)"
      fi
      got="$(grep -o 'id="frame-width">[0-9]*<' <<<"$dom" | grep -o '[0-9][0-9]*' | head -1 || true)"
      if [ -z "$got" ]; then
        fail_run "no frame width after a retry ($url)"
      fi
      if [ "$got" != "$w" ]; then
        fail_run "the frame is $got px wide, not $w ($url)"
      fi

      name="$page"
      [ -z "$tab" ] || name="$name-$tab"
      name="$name-$w-$theme"
      [ -z "$STRESS" ] || name="$name-stress"
      [ "$STATE" = "ready" ] || name="$name-$STATE"
      file="$OUT/$name.png"

      chrome "$win_w" --screenshot="$file" "$url" >/dev/null
      [ -s "$file" ] || fail_run "no picture: $file"
      sips -c "$HEIGHT" "$w" --cropOffset 0 0 "$file" >/dev/null
      echo "wrote $file"
      count=$((count + 1))
    done
  done
done

echo "drew $count pictures"
