#!/usr/bin/env bash
# Ensures the pinned Godot version (.godot-version) and the export templates we
# need (iOS + Web) are installed, then runs Godot with the given arguments.
# Works on Linux (Claude Code cloud, GitHub Actions) and macOS (Xcode Cloud).
#
# Usage: scripts/godot.sh [godot args...]
#        GODOT_PRINT_PATH=1 scripts/godot.sh   # print the binary path only
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="$(tr -d '[:space:]' < "$root/.godot-version")"
release_url="https://github.com/godotengine/godot/releases/download/${version}-stable"
cache="${GODOT_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/mazeborn/godot/$version}"

case "$(uname -s)" in
  Linux)
    asset="Godot_v${version}-stable_linux.x86_64.zip"
    bin="$cache/Godot_v${version}-stable_linux.x86_64"
    templates="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${version}.stable"
    ;;
  Darwin)
    asset="Godot_v${version}-stable_macos.universal.zip"
    bin="$cache/Godot.app/Contents/MacOS/Godot"
    templates="$HOME/Library/Application Support/Godot/export_templates/${version}.stable"
    ;;
  *) echo "godot.sh: unsupported OS $(uname -s)" >&2; exit 1 ;;
esac

download() { # url dest
  echo "godot.sh: downloading $1" >&2
  curl -fSL --retry 4 --retry-delay 2 -o "$2" "$1"
}

if [[ ! -x "$bin" ]]; then
  mkdir -p "$cache"
  download "$release_url/$asset" "$cache/$asset"
  unzip -oq "$cache/$asset" -d "$cache"
  rm -f "$cache/$asset"
  chmod +x "$bin"
fi

if [[ ! -f "$templates/ios.zip" || ! -f "$templates/web_nothreads_release.zip" ]]; then
  # The .tpz holds templates for every platform (~1.3 GB); keep only what we use.
  tpz="$cache/templates.tpz"
  download "$release_url/Godot_v${version}-stable_export_templates.tpz" "$tpz"
  mkdir -p "$templates"
  unzip -ojq "$tpz" 'templates/version.txt' 'templates/ios.zip' \
    'templates/web_nothreads_release.zip' 'templates/web_nothreads_debug.zip' -d "$templates"
  rm -f "$tpz"
fi

if [[ "${GODOT_PRINT_PATH:-}" == 1 ]]; then
  echo "$bin"
  exit 0
fi
exec "$bin" "$@"
