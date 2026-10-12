#!/usr/bin/env bash
# Prepares the Godot game (game_godot/) for the Flutter Android build:
#   android/godot/godot-lib.aar  — the engine (Godot export template, ~100 MB, not in git)
#   android/godot/assets/        — the exported game (res:// of the game, ~85 MB, not in git)
# android/app/build.gradle.kts picks both up when they exist; without them the
# app builds with the old WebView game. Run after any change in game_godot/:
#   ./scripts/godot_android_assets.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_VERSION="$(godot --version | sed -E 's/^([0-9]+\.[0-9]+(\.[0-9]+)?)\.([a-z]+)\..*/\1.\3/')"
if [[ -d "$HOME/.local/share/godot/export_templates/$GODOT_VERSION" ]]; then
  TEMPLATES="$HOME/.local/share/godot/export_templates/$GODOT_VERSION"
elif [[ -d "$HOME/Library/Application Support/Godot/export_templates/$GODOT_VERSION" ]]; then
  TEMPLATES="$HOME/Library/Application Support/Godot/export_templates/$GODOT_VERSION"
else
  TEMPLATES="$HOME/.local/share/godot/export_templates/$GODOT_VERSION"
fi
OUT=android/godot
TMP="$(mktemp -d)"
trap 'git checkout -- game_godot/export_presets.cfg game_godot/scenery 2>/dev/null || true; rm -rf "$TMP"' EXIT
mkdir -p "$OUT"
unzip -oq "$TEMPLATES/android_source.zip" "libs/release/godot-lib.template_release.aar" -d "$TMP"
cp "$TMP/libs/release/godot-lib.template_release.aar" "$OUT/godot-lib.aar"
python3 tools/godot_export/export_ui.py >/dev/null
godot --headless --path game_godot --import >/dev/null 2>&1 || true
if [[ -f "$HOME/.android/debug.keystore" ]]; then
  sed -i.bak -E "s|keystore/release=\".*\"|keystore/release=\"$HOME/.android/debug.keystore\"|" game_godot/export_presets.cfg
  rm -f game_godot/export_presets.cfg.bak
fi
godot --headless --path game_godot --export-release "Android" "$TMP/game.apk" >/dev/null 2>&1
# Import rewrites uids in the committed scenery .import files: keep them as committed.
git checkout -- game_godot/export_presets.cfg game_godot/scenery 2>/dev/null || true
rm -rf "$OUT/assets"
mkdir -p "$OUT/assets"
(cd "$TMP" && unzip -oq game.apk 'assets/*' -x 'assets/dexopt/*')
cp -R "$TMP/assets/." "$OUT/assets/"
echo "godot: $(du -sh "$OUT/assets" | cut -f1) assets, engine $(du -h "$OUT/godot-lib.aar" | cut -f1)"
