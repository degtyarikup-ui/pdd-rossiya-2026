#!/usr/bin/env bash
# Build/install the dev app and run real Android RemoteViews/host regression checks.
# Usage: tools/widgets/check_android_widgets.sh [adb-serial]
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/android_env.sh
sdk_path=$(python3 tools/android_build/environment.py --sdk)
adb_bin="$sdk_path/platform-tools/adb"
widget_test_device=${1:-${ANDROID_SERIAL:-}}
if [[ -z "$widget_test_device" ]]; then
  widget_test_device=$("$adb_bin" devices | awk '$2 == "device" {print $1}')
fi
if [[ -z "$widget_test_device" || "$widget_test_device" == *$'\n'* ]]; then
  echo 'Connect one authorized Android phone, or pass its adb serial.' >&2
  exit 2
fi
"$adb_bin" -s "$widget_test_device" get-state >/dev/null
widget_api=$("$adb_bin" -s "$widget_test_device" shell getprop ro.build.version.sdk | tr -d '\r')
if (( widget_api < 29 )); then
  echo 'The complete host-binding test requires Android 10 (API 29) or newer.' >&2
  exit 2
fi
mkdir -p output/widget-smoke
widget_test_commit=$(git rev-parse --short HEAD)
widget_test_number=$(date -u +%s)
widget_dart_defines=$(python3 - "$widget_test_commit" <<'PY'
import base64, sys
print(base64.b64encode(('GIT_COMMIT=' + sys.argv[1]).encode()).decode())
PY
)
flutter build apk --debug --flavor ru --no-pub -Pdev --target-platform=android-arm64 \
  --build-number="$widget_test_number" --dart-define="GIT_COMMIT=$widget_test_commit" \
  > output/widget-smoke/app-build.log 2>&1
./android/gradlew -p android :app:assembleRuDebugAndroidTest -Pdev \
  -Ptarget-platform=android-arm64 "-Pdart-defines=$widget_dart_defines" \
  > output/widget-smoke/test-build.log 2>&1
"$adb_bin" -s "$widget_test_device" install -r build/app/outputs/flutter-apk/app-ru-debug.apk
"$adb_bin" -s "$widget_test_device" install -r build/app/outputs/apk/androidTest/ru/debug/app-ru-debug-androidTest.apk
"$adb_bin" -s "$widget_test_device" shell am instrument -w \
  ru.pdd.pdd_app.dev.test/ru.pdd.pdd_app.WidgetSmokeInstrumentation \
  > output/widget-smoke/result.txt
# am instrument can exit successfully even when the instrumentation found errors.
python3 - output/widget-smoke/result.txt <<'PY'
from pathlib import Path
import re, sys
report = Path(sys.argv[1]).read_text()
print(report)
result = re.search(r'Passed: (\d+); failed: (\d+)', report)
if result is None or int(result.group(2)):
    raise SystemExit(1)
PY
"$adb_bin" -s "$widget_test_device" shell am start -W \
  -n ru.pdd.pdd_app.dev/ru.pdd.pdd_app.MainActivity
