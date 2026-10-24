#!/usr/bin/env bash
# Fresh web engine/game package. Importers run in a private project snapshot.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v godot >/dev/null || { echo "Нет Godot; выполните ./scripts/setup_game.sh"; exit 1; }
[[ "$(godot --version)" == 4.7.2.stable.* ]] || { echo "Нужен Godot 4.7.2 Standard"; exit 1; }
mkdir -p scratch output/godot build/web
TMP="$(mktemp -d "$PWD/scratch/godot-web.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
STAGE="$TMP/project"
PACKAGE="$TMP/package"
LOG="$PWD/output/godot/web-export.log"
mkdir -p "$STAGE/tools/godot_export" "$STAGE/assets/audio" "$PACKAGE"
rsync -a --exclude='.godot' --exclude='network/preview' --exclude='network/history' game_godot "$STAGE/"
cp tools/godot_export/export_{ui,question_images,question_audio}.py "$STAGE/tools/godot_export/"
ln -s "$PWD/assets/countries" "$STAGE/assets/countries"
ln -s "$PWD/assets/audio/feed" "$STAGE/assets/audio/feed"
ln -s "$PWD/assets/audio/game_questions" "$STAGE/assets/audio/game_questions"
ln -s "$PWD/lib" "$STAGE/lib"
mkdir -p "$STAGE/assets/images"
ln -s "$PWD/assets/images/achievements" "$STAGE/assets/images/achievements"
ln -s "$PWD/assets/images/fire.svg" "$STAGE/assets/images/fire.svg"
python3 "$STAGE/tools/godot_export/export_ui.py"
python3 "$STAGE/tools/godot_export/export_question_images.py"
python3 "$STAGE/tools/godot_export/export_question_audio.py" --check
if ! godot --headless --path "$STAGE/game_godot" --import >"$LOG" 2>&1 || grep -Eq '^(SCRIPT ERROR:|ERROR:)' "$LOG"; then
  tail -60 "$LOG"; echo "Ошибка импорта Godot; журнал: $LOG"; exit 1
fi
if ! godot --headless --path "$STAGE/game_godot" --export-release "Web" "$PACKAGE/index.html" >>"$LOG" 2>&1 || grep -Eq '^(SCRIPT ERROR:|ERROR:)' "$LOG"; then
  tail -60 "$LOG"; echo "Ошибка экспорта Godot; журнал: $LOG"; exit 1
fi
for required in index.html index.js index.wasm index.pck; do
  [[ -s "$PACKAGE/$required" ]] || { echo "Ошибка экспорта Godot: отсутствует $required; журнал: $LOG"; exit 1; }
done
# PackFiles fetches each junction beside the pack; the Flutter assets hold the
# original question pictures and shared answer/voice audio.
(cd "$STAGE/game_godot/situations" && find . -mindepth 2 -maxdepth 2 -type f \
  \( -name scene.json -o -name scene.glb -o -name road.png -o -name 'light_*.glb' -o -name 'actor_*.glb' -o -name guide.glb \) \
  | sed 's|^./||') > "$TMP/scenes.txt"
mkdir -p "$PACKAGE/situations"
rsync -a --files-from="$TMP/scenes.txt" "$STAGE/game_godot/situations/" "$PACKAGE/situations/"
rm -rf build/web/godot
mv "$PACKAGE" build/web/godot
echo "Godot web: $(du -sh build/web/godot | cut -f1)"
