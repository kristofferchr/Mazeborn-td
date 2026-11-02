#!/usr/bin/env bash
# Runs all headless tests in game/tests (test_*.gd, methods test_*).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
"$root/scripts/godot.sh" --headless --path "$root/game" --import >/dev/null 2>&1
"$root/scripts/godot.sh" --headless --path "$root/game" -s res://tests/runner.gd
