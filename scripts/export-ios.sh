#!/usr/bin/env bash
# Exports the Godot project as an Xcode project into ios/ (no .ipa; Xcode or
# Xcode Cloud builds and signs it). Runs on Linux and macOS.
#
# Usage: scripts/export-ios.sh [build-number]
#   build-number defaults to $CI_BUILD_NUMBER (set by Xcode Cloud), else 1.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
build="${1:-${CI_BUILD_NUMBER:-1}}"
[[ "$build" =~ ^[0-9]+$ ]] || { echo "export-ios.sh: invalid build number '$build'" >&2; exit 1; }

presets="$root/game/export_presets.cfg"
backup="$(mktemp)"
cp "$presets" "$backup"
trap 'cp "$backup" "$presets"; rm -f "$backup"' EXIT
sed -i.bak "s/^application\/version=.*/application\/version=\"$build\"/" "$presets" && rm -f "$presets.bak"

"$root/scripts/godot.sh" --headless --path "$root/game" --import
"$root/scripts/godot.sh" --headless --path "$root/game" --export-release "iOS" "$root/ios/Mazeborn.ipa"

for f in Mazeborn.xcodeproj/project.pbxproj Mazeborn.pck Mazeborn.xcframework; do
  [[ -e "$root/ios/$f" ]] || { echo "export-ios.sh: missing ios/$f after export" >&2; exit 1; }
done
echo "export-ios.sh: exported ios/Mazeborn.xcodeproj (build $build)"
