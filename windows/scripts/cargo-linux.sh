#!/usr/bin/env bash
# Runs cargo for the Windows/Linux app inside a Linux container, for anyone
# working on a Mac: the Tauri app only builds for Windows and Linux. Needs
# Docker Desktop running. Examples, from anywhere in the repository:
#
#   windows/scripts/cargo-linux.sh test -p notchmeow ai::router::
#   windows/scripts/cargo-linux.sh test --workspace
#
# The first run builds a small image with the app's Linux build dependencies and
# Python (the AI tests run the shared fixtures and the fake model server).
# Linux build output stays in Docker volumes, never in your windows/target.
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
image="notchmeow-linux-dev"

if ! docker image inspect "$image" >/dev/null 2>&1; then
  docker build -t "$image" - <<'DOCKERFILE'
FROM rust:1-bookworm
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libwebkit2gtk-4.1-dev libgtk-layer-shell-dev libayatana-appindicator3-dev \
      librsvg2-dev libssl-dev libdbus-1-dev python3 \
 && rm -rf /var/lib/apt/lists/*
DOCKERFILE
fi

# tauri-build refuses to run until the relay it bundles exists, so build it first.
exec docker run --rm \
  -v "$repo":/repo \
  -v notchmeow-linux-target:/repo/windows/target \
  -v notchmeow-linux-cargo:/usr/local/cargo/registry \
  -w /repo/windows \
  "$image" \
  bash -c 'cargo build --release -q -p notchmeow-hook && cargo "$@"' cargo-linux "$@"
