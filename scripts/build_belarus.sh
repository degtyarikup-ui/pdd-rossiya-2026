#!/usr/bin/env bash
# Standalone development app only; no store upload or production services.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if ! command -v flutter >/dev/null; then
  if [[ -x "$HOME/flutter/bin/flutter" ]]; then
    export PATH="$HOME/flutter/bin:$PATH"
  else
    echo 'Flutter not found. Add its bin directory to PATH.' >&2
    exit 1
  fi
fi
flutter pub get
dart tools/multi_app/check_boundaries.dart
cd apps/belarus
dart tools/validate_content.dart assets/countries/by/catalog.json
case "${1:-apk}" in
  apk)
    flutter build apk --release --target-platform android-arm64
    python3 ../../tools/multi_app/check_artifact.py build/app/outputs/flutter-apk/app-release.apk --country by
    ;;
  ios)
    flutter build ios --release --no-codesign
    python3 ../../tools/multi_app/check_artifact.py build/ios/iphoneos/Runner.app --country by
    ;;
  web)
    flutter build web --release --no-wasm-dry-run
    python3 ../../tools/multi_app/check_artifact.py build/web --country by
    ;;
  *) echo 'Usage: scripts/build_belarus.sh apk|ios|web (development only)' >&2; exit 2 ;;
esac
