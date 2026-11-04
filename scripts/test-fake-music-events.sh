#!/usr/bin/env bash
# The owner's fake music events (scripts/fake-music-events.swift): its dry run of the "both" scenario prints exactly the 11 lines below, and an unknown scenario exits 2.
# Only --dry-run is ever run here: the sender posts nothing and talks to no music app.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-fake-music.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

swiftc -swift-version 6 scripts/fake-music-events.swift -o "$TEST_DIR/fake-music"

expected="post com.apple.Music.playerInfo Playing Test Song (Apple Music)
wait 3
post com.spotify.client.PlaybackStateChanged Playing Test Song (Spotify)
wait 3
post com.spotify.client.PlaybackStateChanged Paused Test Song (Spotify)
wait 3
post com.apple.Music.playerInfo Paused Test Song (Apple Music)
wait 3
post com.spotify.client.PlaybackStateChanged Stopped Test Song (Spotify)
wait 3
post com.apple.Music.playerInfo Stopped Test Song (Apple Music)"

got="$("$TEST_DIR/fake-music" both --dry-run)"
if [ "$got" != "$expected" ]; then
    echo "the dry run of the both scenario differs from the 11 expected lines"
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$got") || true
    exit 1
fi
[ "$(printf '%s\n' "$got" | wc -l | tr -d ' ')" = "11" ] || { echo "the dry run does not print 11 lines"; exit 1; }

status=0
"$TEST_DIR/fake-music" nope --dry-run > /dev/null 2>&1 || status=$?
[ "$status" = "2" ] || { echo "an unknown scenario exits $status, expected 2"; exit 1; }

echo "fake music events: the both scenario prints its 11 lines (dry run), an unknown scenario exits 2"
