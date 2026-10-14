#!/usr/bin/env bash
# Prepares the Godot game (game_godot/) for the Flutter Android build:
#   android/godot/godot-lib.aar  — the engine (Godot export template, ~100 MB, not in git)
#   android/godot/assets/        — the exported game (res:// of the game, ~85 MB, not in git)
# android/app/build.gradle.kts picks both up when they exist; without them the
# app builds with the Godot game unavailable. Run after any change in game_godot/:
#   ./scripts/godot_android_assets.sh
set -euo pipefail
cd "$(dirname "$0")/.."
command -v godot >/dev/null || { echo "Нет godot в PATH; см. docs/build/android.md"; exit 1; }
GODOT_VERSION="$(godot --version | sed -E 's/^([0-9]+\.[0-9]+(\.[0-9]+)?)\.([a-z]+)\..*/\1.\3/')"
[[ "$GODOT_VERSION" == 4.7.2.stable ]] || { echo "Нужен Godot 4.7.2 Standard, установлен $GODOT_VERSION"; exit 1; }
if [[ -d "$HOME/.local/share/godot/export_templates/$GODOT_VERSION" ]]; then
  TEMPLATES="$HOME/.local/share/godot/export_templates/$GODOT_VERSION"
elif [[ -d "$HOME/Library/Application Support/Godot/export_templates/$GODOT_VERSION" ]]; then
  TEMPLATES="$HOME/Library/Application Support/Godot/export_templates/$GODOT_VERSION"
else
  TEMPLATES="$HOME/.local/share/godot/export_templates/$GODOT_VERSION"
fi
OUT=android/godot
[[ -f "$TEMPLATES/android_source.zip" ]] || { echo "Нет шаблонов экспорта: $TEMPLATES/android_source.zip (Godot → Manage Export Templates)"; exit 1; }
mkdir -p scratch output/godot
TMP="$(mktemp -d "$PWD/scratch/godot-android.XXXXXX")"
LOG="$PWD/output/godot/android-export.log"
cp game_godot/export_presets.cfg "$TMP/export_presets.cfg"
cp -R game_godot/scenery "$TMP/scenery"
restore_inputs() {
  cp "$TMP/export_presets.cfg" game_godot/export_presets.cfg
  cp -R "$TMP/scenery/." game_godot/scenery/
  rm -rf "$TMP"
}
trap restore_inputs EXIT
mkdir -p "$OUT"
unzip -oq "$TEMPLATES/android_source.zip" "libs/release/godot-lib.template_release.aar" -d "$TMP"
cp "$TMP/libs/release/godot-lib.template_release.aar" "$OUT/godot-lib.aar"
python3 tools/godot_export/export_ui.py >/dev/null
python3 tools/godot_export/export_question_images.py
python3 tools/godot_export/export_question_audio.py
if ! godot --headless --path game_godot --import >"$LOG" 2>&1 || grep -Eq '^(SCRIPT ERROR:|ERROR:)' "$LOG"; then
  tail -60 "$LOG"; echo "Ошибка импорта Godot; полный журнал: $LOG"; exit 1
fi
# This APK is only a container for res:// assets, so no signing key is needed.
python3 - <<'PY'
from pathlib import Path
p = Path('game_godot/export_presets.cfg')
s = p.read_text()
start = s.index('[preset.0.options]')
end = s.index('[preset.1]', start)
import os
import re
options = re.sub(r'^package/signed=.*\n', '', s[start:end], flags=re.M)
options = options.replace('[preset.0.options]', '[preset.0.options]\npackage/signed=false')
debug_ks = Path.home() / '.android/debug.keystore'
if debug_ks.is_file():
    options = re.sub(r'keystore/release="[^"]*"', f'keystore/release="{debug_ks}"', options)
p.write_text(s[:start] + options + s[end:])
PY
if ! godot --headless --path game_godot --export-release "Android" "$TMP/game.apk" >>"$LOG" 2>&1 || grep -Eq '^(SCRIPT ERROR:|ERROR:)' "$LOG"; then
  tail -60 "$LOG"; echo "Ошибка экспорта Godot; полный журнал: $LOG"; exit 1
fi
rm -rf "$OUT/assets"
mkdir -p "$OUT/assets"
(cd "$TMP" && unzip -oq game.apk 'assets/*' -x 'assets/dexopt/*')
cp -R "$TMP/assets/." "$OUT/assets/"
echo "godot: $(du -sh "$OUT/assets" | cut -f1) assets, engine $(du -h "$OUT/godot-lib.aar" | cut -f1)"
