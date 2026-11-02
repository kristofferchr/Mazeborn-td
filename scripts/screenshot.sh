#!/usr/bin/env bash
# Renders a scene offscreen (xvfb + Mesa, Compatibility renderer) and saves a PNG.
# Usage: scripts/screenshot.sh <out.png> [res://scene.tscn] [frames] [WxH]
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
scene="${2:-res://main.tscn}"; frames="${3:-60}"; size="${4:-1280x720}"
"$root/scripts/godot.sh" --headless --path "$root/game" --import >/dev/null
bin="$(GODOT_PRINT_PATH=1 "$root/scripts/godot.sh")"
xvfb-run -a -s "-screen 0 ${size}x24" "$bin" --path "$root/game" --audio-driver Dummy \
  --rendering-driver opengl3 --resolution "$size" -s res://tools/screenshot.gd -- "$out" "$scene" "$frames"
