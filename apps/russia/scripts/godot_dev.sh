#!/usr/bin/env bash
# Godot game (game_godot/): export and install on the test phones.
#
#   ./scripts/godot_dev.sh android   # APK -> Pixel over Wi-Fi (adb), launch
#   ./scripts/godot_dev.sh ios       # Xcode project -> build -> iPhone (cable), launch
#   ./scripts/godot_dev.sh all
#   ./scripts/godot_dev.sh web       # the game for the site: build/web/godot/ (after build.sh web)
#
# Separate app ru.pdd.godotspike: the store app is not touched.
set -euo pipefail
cd "$(dirname "$0")/.."
ADB=${ADB:-/opt/homebrew/share/android-commandlinetools/platform-tools/adb}
PIXEL=${PIXEL:-$(cat .dev-device 2>/dev/null || echo 192.168.31.143:5555)}
IPHONE=${IPHONE:-00008030-0005785A01D3C02E}
OUT=output/godot
mkdir -p "$OUT"
# Native standalone games have no Flutter assets. Links are only export inputs.
trap 'python3 tools/godot_export/export_question_images.py >/dev/null; python3 tools/godot_export/export_question_audio.py --clean-links' EXIT

android() {
  python3 tools/godot_export/export_question_images.py --standalone
  python3 tools/godot_export/export_question_audio.py --standalone
  godot --headless --path game_godot --import >/dev/null 2>&1 || true
  godot --headless --path game_godot --export-release "Android" "../$OUT/pdd-game-spike.apk" 2>&1 | grep -E "ERROR" | grep -v "icon\|filter" || true
  "$ADB" connect "$PIXEL" >/dev/null 2>&1 || true
  "$ADB" -s "$PIXEL" install -r "$OUT/pdd-game-spike.apk" | tail -1
  "$ADB" -s "$PIXEL" shell monkey -p ru.pdd.godotspike -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  echo "Android: запущено на $PIXEL"
}

ios() {
  python3 tools/godot_export/export_question_images.py --standalone
  python3 tools/godot_export/export_question_audio.py --standalone
  godot --headless --path game_godot --import >/dev/null 2>&1 || true
  rm -rf "$OUT/ios"; mkdir -p "$OUT/ios"
  godot --headless --path game_godot --export-release "iOS" "../$OUT/ios/PDDGameSpike.xcodeproj" >/dev/null 2>&1 || true
  (cd "$OUT/ios" && xcodebuild -project PDDGameSpike.xcodeproj -scheme PDDGameSpike -configuration Release \
    -destination "id=$IPHONE" -allowProvisioningUpdates DEVELOPMENT_TEAM=6T66V45XC7 CODE_SIGN_STYLE=Automatic \
    CODE_SIGN_IDENTITY="Apple Development" -derivedDataPath build build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)")
  xcrun devicectl device install app --device "$IPHONE" "$OUT/ios/build/Build/Products/Release-iphoneos/PDDGameSpike.app" >/dev/null
  xcrun devicectl device process launch --device "$IPHONE" ru.pdd.godotspike >/dev/null 2>&1 || echo "iOS: установлено; телефон заблокирован — откройте приложение вручную"
  echo "iOS: запущено на $IPHONE"
}

# Web (the site, folder /app/godot/ next to the Flutter app). The pack holds the
# engine, models, networks and the question list (~10 MB); the junction scenes
# are plain files next to it; ticket pictures use the shared Flutter assets
# (game_godot/scripts/pack_files.gd). Nothreads: no SharedArrayBuffer needed.
web() {
  python3 tools/godot_export/export_question_images.py
  python3 tools/godot_export/export_question_audio.py
  local out="build/web/godot"
  command -v godot >/dev/null || { echo "Web: нет godot в PATH"; exit 1; }
  [ -d "game_godot/situations" ] || { echo "Web: нет game_godot/situations (они лежат в git: git pull / проверьте клон)"; exit 1; }
  rm -rf "$out"; mkdir -p "$out"
  godot --headless --path game_godot --import >/dev/null 2>&1 || true
  godot --headless --path game_godot --export-release "Web" "../$out/index.html" 2>&1 | grep -E "ERROR" || true
  [ -f "$out/index.pck" ] || { echo "Web: экспорт не получился"; exit 1; }
  local list
  list="$(mktemp "${TMPDIR:-/tmp}/godot-web-files.XXXXXX")"
  # Only what the game reads per junction (game_godot/scripts/situation.gd).
  (cd game_godot/situations && find . -mindepth 2 -maxdepth 2 -type f \
    \( -name scene.json -o -name scene.glb -o -name road.png -o -name 'light_*.glb' -o -name 'actor_*.glb' -o -name guide.glb \)) \
    | sed 's|^\./||' > "$list"
  mkdir -p "$out/situations"
  rsync -a --files-from="$list" game_godot/situations/ "$out/situations/"
  rm -f "$list"
  # Pictures are already in build/web/assets/assets/countries/ru/images/questions_ab/.
  echo "Web: $out ($(du -sh "$out" | cut -f1); pack $(du -h "$out/index.pck" | cut -f1), engine $(du -h "$out/index.wasm" | cut -f1))"
}

case "${1:-all}" in
  android) android ;;
  ios) ios ;;
  web) web ;;
  all) android; ios ;;
  *) echo "usage: $0 android|ios|all|web"; exit 1 ;;
esac
