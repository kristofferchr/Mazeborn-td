#!/usr/bin/env bash
# Xcode Cloud: runs after the repository is cloned and before xcodebuild.
# Downloads the pinned Godot version and regenerates ios/Mazeborn.xcodeproj,
# the engine xcframework and the game data (Mazeborn.pck) from game/.
set -euo pipefail
cd "${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/../.." && pwd)}"
scripts/export-ios.sh "${CI_BUILD_NUMBER:-1}"
