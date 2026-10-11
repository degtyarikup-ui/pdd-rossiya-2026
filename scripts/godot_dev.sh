#!/usr/bin/env bash
# Godot game (game_godot/): export and install on the test phones.
#
#   ./scripts/godot_dev.sh android   # APK -> Pixel over Wi-Fi (adb), launch
#   ./scripts/godot_dev.sh ios       # Xcode project -> build -> iPhone (cable), launch
#   ./scripts/godot_dev.sh all
#   ./scripts/godot_dev.sh export    # re-export models from the WebView game first
#
# Separate app ru.pdd.godotspike: the store app is not touched.
set -euo pipefail
cd "$(dirname "$0")/.."
ADB=${ADB:-/opt/homebrew/share/android-commandlinetools/platform-tools/adb}
PIXEL=${PIXEL:-$(cat .dev-device 2>/dev/null || echo 192.168.31.143:5555)}
IPHONE=${IPHONE:-00008030-0005785A01D3C02E}
OUT=output/godot
mkdir -p "$OUT"

export_models() { NODE_PATH="$PWD/node_modules" node tools/godot_export/export_models.cjs; }

android() {
  godot --headless --path game_godot --import >/dev/null 2>&1 || true
  godot --headless --path game_godot --export-release "Android" "../$OUT/pdd-game-spike.apk" 2>&1 | grep -E "ERROR" | grep -v "icon\|filter" || true
  "$ADB" connect "$PIXEL" >/dev/null 2>&1 || true
  "$ADB" -s "$PIXEL" install -r "$OUT/pdd-game-spike.apk" | tail -1
  "$ADB" -s "$PIXEL" shell monkey -p ru.pdd.godotspike -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  echo "Android: запущено на $PIXEL"
}

ios() {
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

case "${1:-all}" in
  export) export_models ;;
  android) android ;;
  ios) ios ;;
  all) android; ios ;;
  *) echo "usage: $0 android|ios|all|export"; exit 1 ;;
esac
