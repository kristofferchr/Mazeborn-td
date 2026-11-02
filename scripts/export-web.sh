#!/usr/bin/env bash
# Exports the single-threaded web build (works on GitHub Pages without
# COOP/COEP headers). Usage: scripts/export-web.sh [out-dir]   (default build/web)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$(mkdir -p "${1:-$root/build/web}" && cd "${1:-$root/build/web}" && pwd)"
"$root/scripts/godot.sh" --headless --path "$root/game" --import
"$root/scripts/godot.sh" --headless --path "$root/game" --export-release "Web" "$out/index.html"
echo "export-web.sh: $out/index.html"
