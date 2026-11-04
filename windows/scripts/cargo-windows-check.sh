#!/usr/bin/env bash
# Type-checks the Windows build (x86_64-pc-windows-gnu) from a Mac, inside the
# same Linux container as cargo-linux.sh: `cargo check` of the whole workspace,
# every target, offline. It proves the Windows-only Rust compiles; it does not
# link or run it (CI's windows-tests.yml and a real PC do that).
#
#   windows/scripts/cargo-windows-check.sh                   # the whole workspace
#   windows/scripts/cargo-windows-check.sh --target-dir /repo/windows/target/win-<plan>
#
# Needs the Rust target x86_64-pc-windows-gnu in the container (rustup adds it
# on each run: the first time it downloads it, about 60-80 MB). The crates must
# already be in the notchmeow-linux-cargo volume (run cargo-linux.sh first).
# ring's and tauri-winres's build scripts call a MinGW C compiler and windres;
# check never links, so two stand-ins that only write the empty files those
# scripts expect take their place, and nothing else is downloaded.
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
image="notchmeow-linux-dev"
docker image inspect "$image" >/dev/null 2>&1 || { echo "No $image image: run windows/scripts/cargo-linux.sh once first." >&2; exit 1; }

stub="$(mktemp -d)"
cat > "$stub/x86_64-w64-mingw32-gcc" <<'EOF'
#!/bin/sh
# Check-only stand-in: writes an empty file for -o / -Fo, answers --version.
out=""; prev=""
for a in "$@"; do
  case "$a" in --version|-dumpversion) echo "12.0"; exit 0;; -o?*) out="${a#-o}";; -Fo?*) out="${a#-Fo}";; /Fo?*) out="${a#/Fo}";; esac
  [ "$prev" = "-o" ] && out="$a"; prev="$a"
done
[ -n "$out" ] && mkdir -p "$(dirname "$out")" && : > "$out"
exit 0
EOF
cp "$stub/x86_64-w64-mingw32-gcc" "$stub/x86_64-w64-mingw32-windres"
chmod +x "$stub"/*

exec docker run --rm \
  -v "$repo":/repo \
  -v "$stub":/stubcc:ro \
  -v notchmeow-release-win:/repo/windows/target \
  -v notchmeow-linux-cargo:/usr/local/cargo/registry \
  -w /repo/windows \
  -e CARGO_NET_OFFLINE=true \
  -e PATH=/stubcc:/usr/local/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  -e AR_x86_64_pc_windows_gnu=ar \
  "$image" \
  bash -c 'rustup target add x86_64-pc-windows-gnu >/dev/null 2>&1 && mkdir -p target/release && touch target/release/notchmeow-hook.exe && cargo check --offline --workspace --all-targets --target x86_64-pc-windows-gnu "$@"' cargo-windows-check "$@"
