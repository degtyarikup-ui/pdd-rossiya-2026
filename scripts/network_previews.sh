#!/usr/bin/env bash
# Pictures of every junction for the editor background (game_godot/network/preview/<id>.png).
# ONE Godot run for all scenes: the window opens once, off screen, and closes itself.
#   ./scripts/network_previews.sh        (runs in the background; log in output/previews.log)
# Needs game_godot/situations/ (./scripts/godot_dev.sh export).
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root/output" "$root/game_godot/network/preview"
nohup godot --path "$root/game_godot" --resolution 1400x1400 --position 6000,6000 \
  -- --previews --out="$root/game_godot/network/preview" > "$root/output/previews.log" 2>&1 &
echo "previews started (pid $!), log: output/previews.log"
