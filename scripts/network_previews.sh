#!/usr/bin/env bash
# Renders the straight-down picture of every junction (editor background):
#   ./scripts/network_previews.sh [id ...]      ~15 s per scene, windowed Godot
# Needs game_godot/situations/ (./scripts/godot_dev.sh export). Output: game_godot/network/preview/<id>.png
cd "$(dirname "$0")/../game_godot"
mkdir -p network/preview
ids=("$@"); [ ${#ids[@]} -eq 0 ] && ids=($(ls network/*.json | xargs -n1 basename | sed 's/\.json//'))
for id in "${ids[@]}"; do
  ( godot --path . --resolution 1400x1400 -- --situation="$id" --topdown="$PWD/network/preview/$id.png" >/dev/null 2>&1 & pid=$!; ( sleep 40; kill $pid 2>/dev/null ) & wait $pid )
  echo "$id"
done
