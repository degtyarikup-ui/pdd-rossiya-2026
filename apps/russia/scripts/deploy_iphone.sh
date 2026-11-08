#!/usr/bin/env bash
set -e

DEVICE_ID="00008030-0005785A01D3C02E"
COUNTRY="${1:-ru}"

echo "🔨 Сборка iOS Release-версии (COUNTRY=${COUNTRY})..."
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || true)"
COMMIT_DEFINE=()
[[ -n "$COMMIT" ]] && COMMIT_DEFINE=(--dart-define=GIT_COMMIT="${COMMIT}")
flutter build ios --release --dart-define=COUNTRY="${COUNTRY}" "${COMMIT_DEFINE[@]}"

APP_PATH="build/ios/Release-iphoneos/Runner.app"

if [ -d "${APP_PATH}" ]; then
  echo "📲 Установка приложения на iPhone (${DEVICE_ID})..."
  xcrun devicectl device install app --device "${DEVICE_ID}" "${APP_PATH}"

  echo "🚀 Запуск приложения на iPhone..."
  xcrun devicectl device process launch --device "${DEVICE_ID}" ru.pdd.pddApp
  echo "✅ Успешно обновлено и запущено!"
else
  echo "❌ Ошибка: не найден бандл ${APP_PATH}"
  exit 1
fi
