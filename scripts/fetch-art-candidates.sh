#!/usr/bin/env bash
# Downloads the candidate 3D asset packs (all CC0, see docs/art-assets.md) and
# copies the models used by res://tools/art_lineup.tscn and art_mock.tscn into
# the git-ignored game/art_candidates/.
# Usage: scripts/fetch-art-candidates.sh [cache dir]
# Needs network access to github.com, itch.io and quaternius.itch.io, plus
# `pip install requests`.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cache="${1:-$HOME/.cache/mazeborn/art}"
dest="$root/game/art_candidates"
mkdir -p "$cache"

kaykit() {  # repo name
	[ -d "$cache/$1" ] || git clone -q --depth 1 "https://github.com/KayKit-Game-Assets/$1" "$cache/$1"
}
itch() {  # slug
	[ -f "$cache/$1.zip" ] || python3 "$root/scripts/itch_download.py" quaternius "$1" "$cache/$1.zip"
	[ -d "$cache/$1" ] || unzip -q -o "$cache/$1.zip" -d "$cache/$1"
}

kaykit KayKit-Character-Pack-Skeletons-1.0
kaykit KayKit-Character-Pack-Adventures-1.0
kaykit KayKit-Medieval-Hexagon-Pack-1.0
itch lowpoly-animated-monsters
itch animated-easy-enemies
itch stylized-nature-megakit

rm -rf "$dest"
mkdir -p "$dest"/{kaykit,kk_hex,q_monsters,q_easy,q_nature}
find "$cache"/KayKit-Character-Pack-{Skeletons,Adventures}-1.0 -name '*.glb' -exec cp {} "$dest/kaykit/" \;
hex="$cache/KayKit-Medieval-Hexagon-Pack-1.0/addons/kaykit_medieval_hexagon_pack/Assets/gltf"
cp "$(find "$cache/KayKit-Medieval-Hexagon-Pack-1.0" -name hexagons_medieval.png | head -1)" "$dest/kk_hex/"
for name in building_tower_A_blue building_tower_B_blue building_tower_catapult_blue \
	tree_single_A tree_single_B trees_A_medium; do
	f="$(find "$hex" -name "$name.gltf" | head -1)"
	cp "$f" "${f%.gltf}.bin" "$dest/kk_hex/"
done
cp "$cache"/lowpoly-animated-monsters/FBX/*.fbx "$dest/q_monsters/"
cp "$cache"/animated-easy-enemies/*/FBX/*.fbx "$dest/q_easy/"
nature="$(dirname "$(find "$cache/stylized-nature-megakit" -name CommonTree_2.gltf | head -1)")"
cp "$nature"/*.gltf "$nature"/*.bin "$nature"/*.png "$dest/q_nature/"
echo "Candidates in $dest ($(du -sh "$dest" | cut -f1))"
