#!/usr/bin/env bash
# Сборка приложения для страны: ./scripts/build.sh {ru|by} {aab|web}
#
# Единый код — разные страны. Страна задаётся одновременно:
#  - Android flavor (applicationId, имя приложения, иконка),
#  - --dart-define=COUNTRY (правила экзамена, контент, тексты).
set -euo pipefail

COUNTRY="${1:?usage: build.sh ru|by aab|web}"
TARGET="${2:?usage: build.sh ru|by aab|web}"

case "$COUNTRY" in
  ru|by) ;;
  *) echo "unknown country: $COUNTRY (expected ru|by)"; exit 1 ;;
esac

export PATH="$HOME/flutter/bin:$PATH"
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
export PATH="$JAVA_HOME/bin:$PATH"

cd "$(dirname "$0")/.."

case "$TARGET" in
  aab)
    flutter build appbundle --release \
      --flavor "$COUNTRY" \
      --dart-define=COUNTRY="$COUNTRY"
    echo "AAB: build/app/outputs/bundle/${COUNTRY}Release/app-${COUNTRY}-release.aab"
    ;;
  web)
    flutter build web --release --base-href "/" --no-wasm-dry-run \
      --dart-define=COUNTRY="$COUNTRY"
    echo "Web: build/web (COUNTRY=$COUNTRY)"
    ;;
  *) echo "unknown target: $TARGET (expected aab|web)"; exit 1 ;;
esac
