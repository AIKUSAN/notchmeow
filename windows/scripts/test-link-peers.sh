#!/usr/bin/env bash
# Builds the link_peer example and runs windows/scripts/link-peers.sh with it in the Linux container (Docker Desktop must be running). Two processes, real TCP on loopback, real Noise and files.
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
"$repo/windows/scripts/cargo-linux.sh" build --offline --target-dir /repo/windows/target/g2-tauri -p notchmeow --example link_peer
exec docker run --rm --network none \
  -v "$repo":/repo \
  -v notchmeow-linux-target:/repo/windows/target \
  -v notchmeow-linux-cargo:/usr/local/cargo/registry \
  -w /repo/windows \
  notchmeow-linux-dev \
  bash /repo/windows/scripts/link-peers.sh /repo/windows/target/g2-tauri/debug/examples/link_peer
