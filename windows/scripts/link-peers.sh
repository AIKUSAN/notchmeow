#!/usr/bin/env bash
# Two real link_peer processes on this computer (sub-project G2): the same service, Noise, frames, files and TCP as the app, in two processes, each with its own keys in memory. Machine A listens,
# machine B names A on the command line (no mDNS, no credential store: this is the protocol and the files). B pairs with A and both say the digits match; B sends a file and A accepts; B sends a
# second file and A declines. It checks that both showed the same six digits, that A's copy has B's SHA-256 and that the declined file was never written.
#
# usage: windows/scripts/link-peers.sh PATH/TO/link_peer          (windows/scripts/test-link-peers.sh builds it and runs this in the Linux container)
set -euo pipefail
BIN="${1:?usage: link-peers.sh PATH/TO/link_peer}"
W="$(mktemp -d)"
trap 'exec 7>&- 8>&- 2>/dev/null || true; kill $(jobs -p) 2>/dev/null || true; rm -rf "$W"' EXIT
mkfifo "$W/a.in" "$W/b.in"
head -c 300000 /dev/urandom > "$W/one.bin"
head -c 1000 /dev/urandom > "$W/two.bin"
head -c 2000 /dev/urandom > "$W/three of them.bin"   # a name with spaces, in a path with spaces too
sha() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

wait_for() {   # wait_for FILE PATTERN [SECONDS]
  local i; for ((i = 0; i < ${3:-30} * 10; i++)); do grep -qE "$2" "$1" 2>/dev/null && return 0; sleep 0.1; done
  echo "TIMEOUT waiting for '$2' in $1"; echo "--- A"; cat "$W/a.out"; echo "--- B"; cat "$W/b.out"; exit 1
}

PORT=$((20000 + RANDOM % 20000))
"$BIN" "Desk PC" --bind "127.0.0.1:$PORT" --no-mdns < "$W/a.in" > "$W/a.out" 2>&1 &
exec 7> "$W/a.in"
wait_for "$W/a.out" 'Commands:'
echo id >&7; wait_for "$W/a.out" '^[0-9a-f]{32}$'
A_ID="$(grep -E '^[0-9a-f]{32}$' "$W/a.out" | head -1)"
A_FOLDER="$(sed -n 's/.*Received files: //p' "$W/a.out" | head -1)"

"$BIN" "Sam's laptop" --bind 127.0.0.1:0 --peer "$A_ID@127.0.0.1:$PORT/Desk PC" < "$W/b.in" > "$W/b.out" 2>&1 &
exec 8> "$W/b.in"
wait_for "$W/b.out" 'Commands:'
echo visible >&7; echo visible >&8
wait_for "$W/a.out" 'log: listening'; wait_for "$W/b.out" 'log: listening'
wait_for "$W/b.out" '\[0\] Desk PC \(available\)'

echo "pair 0" >&8
wait_for "$W/a.out" 'card: pair'; wait_for "$W/b.out" 'card: pair'
CODE_A="$(grep -o 'code=Some("[0-9]*")' "$W/a.out" | head -1)"; CODE_B="$(grep -o 'code=Some("[0-9]*")' "$W/b.out" | head -1)"
[ -n "$CODE_A" ] && [ "$CODE_A" = "$CODE_B" ] || { echo "the two machines showed different digits: $CODE_A / $CODE_B"; exit 1; }
sleep 1   # a click within 700 ms of a card appearing is ignored (the settle rule)
echo yes >&7; echo yes >&8
wait_for "$W/a.out" 'card: result .*title=Some\("Paired"\)'; wait_for "$W/b.out" 'card: result .*title=Some\("Paired"\)'

echo "send $W/one.bin 0" >&8
wait_for "$W/a.out" 'card: offer.*name=Some\("one.bin"\)'
sleep 1; echo accept >&7
wait_for "$W/a.out" 'card: result .*title=Some\("Received"\)'; wait_for "$W/b.out" 'Finished sending one.bin'
[ "$(sha "$A_FOLDER/one.bin")" = "$(sha "$W/one.bin")" ] || { echo "the received file differs from the one sent"; exit 1; }

echo "send $W/two.bin 0" >&8
wait_for "$W/a.out" 'card: offer.*name=Some\("two.bin"\)'
sleep 1; echo decline >&7
wait_for "$W/b.out" 'send: Desk PC declined two.bin'
[ ! -e "$A_FOLDER/two.bin" ] || { echo "a declined file was written"; exit 1; }

echo "send $W/three of them.bin 0" >&8
wait_for "$W/a.out" 'card: offer.*name=Some\("three of them.bin"\)'
sleep 1; echo accept >&7
wait_for "$W/a.out" 'card: result .*Saved as three of them.bin'; wait_for "$W/b.out" 'Finished sending three of them.bin'
[ "$(sha "$A_FOLDER/three of them.bin")" = "$(sha "$W/three of them.bin")" ] || { echo "the file with spaces in its name differs from the one sent"; exit 1; }
echo quit >&7; echo quit >&8
echo "link peers: ok (same digits on both machines, a file that arrived with its SHA-256, a declined file that was never written, a path with spaces)"
