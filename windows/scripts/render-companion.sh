#!/usr/bin/env bash
# Draws the Companion's pictures for the owner's checkpoint (sub-project F3a-tauri, Task 11): the chat on each scene, cut from the dev server's sample route
# (`chat.html?sample=1&scene=<scene>`, companion/devcompanion.ts). One headless Chrome run per picture, at the picture's own size; the picture is cropped to that size
# with sips and must be at least that big. Not part of CI. It writes to --out, to a throwaway Chrome profile and Vite's log (a mktemp folder, moved to the Trash with
# `trash` at exit). It stops the Vite server it started. It reads no agent's own folder and launches no NotchMeow or Tauri app: the samples are in memory.
#
# usage: render-companion.sh [--out DIR]
set -euo pipefail

usage() {
  echo "usage: render-companion.sh [--out DIR]" >&2
  exit 2
}

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${TMPDIR:-/tmp}/f3a-tauri-pictures"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
PORT="1422"

while [ $# -gt 0 ]; do
  case "$1" in
    --out) [ $# -ge 2 ] || usage; OUT="$2"; shift 2 ;;
    *) usage ;;
  esac
done

# name|scene|width|height: the chat window (chat.html) on one scene. popout is the pop-out window's own size (520 x 640) on the four-message chat.
PICTURES="chat-0|chat-0|640|300
chat-4|chat-4|640|460
chat-8|chat-8|640|560
chat-14|chat-14|640|560
conversations|conversations|640|560
conversations-small|conversations|640|300
quick-running|quick-running|640|460
quick-done|quick-done|640|460
screenshot-chip|screenshot-chip|640|400
folder-read|folder-read|640|400
folder-agent|folder-agent|640|400
cloud-line|cloud-line|640|460
popout|chat-4|520|640"

[ -x "$CHROME" ] || { echo "Chrome not found: $CHROME" >&2; exit 1; }

mkdir -p "$OUT"
PROFILE="$(mktemp -d "${TMPDIR:-/tmp}/companion-chrome.XXXXXX")"
LOG="$PROFILE/vite.log"
CHROME_LOG="$PROFILE/chrome.log"

# A failed run says what it was and shows the last lines of Chrome's log (its stderr).
fail_run() {
  echo "$1" >&2
  tail -5 "$CHROME_LOG" >&2 2>/dev/null || true
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

if curl -s -o /dev/null "http://127.0.0.1:$PORT/chat.html"; then
  echo "port $PORT is already in use: stop the server on it first" >&2
  exit 1
fi

cd "$ROOT"
npx --no-install vite --port "$PORT" --strictPort --host 127.0.0.1 >"$LOG" 2>&1 &
SERVER=$!

ready=""
for _ in $(seq 1 60); do
  if curl -s -o /dev/null "http://127.0.0.1:$PORT/chat.html"; then
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

# One headless Chrome run at the picture's window size.
chrome() {
  local win_w="$1" win_h="$2"; shift 2
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --no-first-run --disable-extensions \
    --user-data-dir="$PROFILE" --window-size="$win_w,$win_h" --virtual-time-budget=5000 "$@" 2>>"$CHROME_LOG" </dev/null
}

count=0
while IFS='|' read -r name scene w h; do
  url="http://127.0.0.1:$PORT/chat.html?sample=1&scene=$scene"
  file="$OUT/$name.png"
  chrome "$w" "$h" --screenshot="$file" "$url" >/dev/null || true
  [ -s "$file" ] || fail_run "no picture: $file ($url)"

  # The picture must be at least the size asked for: it is cut down to exactly that size, never stretched.
  got_w="$(sips -g pixelWidth "$file" | awk '/pixelWidth/ {print $2}')"
  got_h="$(sips -g pixelHeight "$file" | awk '/pixelHeight/ {print $2}')"
  if [ "$got_w" -lt "$w" ] || [ "$got_h" -lt "$h" ]; then
    fail_run "the picture is ${got_w}x${got_h}, smaller than ${w}x${h} ($url)"
  fi
  sips -c "$h" "$w" --cropOffset 0 0 "$file" >/dev/null
  echo "wrote $file (${w}x${h})"
  count=$((count + 1))
done <<EOF
$PICTURES
EOF

echo "drew $count pictures"
