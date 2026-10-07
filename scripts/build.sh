#!/usr/bin/env bash
# Сборка приложения: ./scripts/build.sh ru {aab|apk|ipa|web}
#
# Страна одна — Россия. Аргумент `ru` оставлен, чтобы не ломать привычные
# команды: он задаёт Android flavor и --dart-define=COUNTRY.
set -euo pipefail

COUNTRY="${1:?usage: build.sh ru aab|apk|ipa|web}"
TARGET="${2:?usage: build.sh ru aab|apk|ipa|web}"

case "$COUNTRY" in
  ru) ;;
  *) echo "unknown country: $COUNTRY (only ru)"; exit 1 ;;
esac

export PATH="/opt/homebrew/bin:$HOME/flutter/bin:$PATH"
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
export PATH="$JAVA_HOME/bin:$PATH"

cd "$(dirname "$0")/.."

# Опциональное уведомление о новой установке (Telegram). Параметры берутся из
# переменных окружения и в git не попадают. Если не заданы — фича «спит» (no-op):
#   export INSTALL_NOTIFY_URL=https://pdd-install-notifier.<субдомен>.workers.dev
#   export INSTALL_NOTIFY_SECRET=...   # только если на воркере задан SHARED_SECRET
NOTIFY_DEFINES=()
if [[ -n "${INSTALL_NOTIFY_URL:-}" ]]; then
  NOTIFY_DEFINES+=(--dart-define=INSTALL_NOTIFY_URL="$INSTALL_NOTIFY_URL")
fi
# Ключ приложения: без него воркер не пускает сборку к платным функциям
# (разбор от ИИ идёт через наш ключ Gemini). Лежит в secrets/ — папка в
# .gitignore, потому что репозиторий проекта публичный.
if [[ -z "${INSTALL_NOTIFY_SECRET:-}" && -f "secrets/install_notify_secret.txt" ]]; then
  INSTALL_NOTIFY_SECRET="$(cat "secrets/install_notify_secret.txt")"
fi
if [[ -n "${INSTALL_NOTIFY_SECRET:-}" ]]; then
  NOTIFY_DEFINES+=(--dart-define=INSTALL_NOTIFY_SECRET="$INSTALL_NOTIFY_SECRET")
else
  echo "Ошибка: отсутствует ключ приложения; release без ИИ и синхронизации не собираем." >&2
  exit 1
fi

# Дополнительные параметры сборки через окружение.
# GAME_DEBUG / NOTIF_TEST / SCREEN не включают отладку в release.
EXTRA_DEFINES_ARR=()
if [[ "$TARGET" == "web" ]]; then
  # Public OAuth client ID (not a client secret). Default is in AuthService.
  if [[ -n "${GOOGLE_WEB_CLIENT_ID:-}" ]]; then
    EXTRA_DEFINES_ARR+=(--dart-define=GOOGLE_WEB_CLIENT_ID="$GOOGLE_WEB_CLIENT_ID")
  fi
fi
# Firebase client IDs are configured per country; sender private keys are never
# included in the application. Builds without this optional file keep pushes off.
FIREBASE_DEFINES="secrets/firebase/$COUNTRY.defines.json"
if [[ "$TARGET" != "web" && -f "$FIREBASE_DEFINES" ]]; then
  EXTRA_DEFINES_ARR+=(--dart-define-from-file="$FIREBASE_DEFINES")
fi
if [[ -n "${EXTRA_DEFINES:-}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_DEFINES_ARR+=($EXTRA_DEFINES)
fi

# Контент страны обязан лежать внутри артефакта. Проверка дешёвая, а цена
# ошибки — релиз, где все экраны пишут «не удалось загрузить данные».
verify_archive() {
  local archive="$1"
  local needle="assets/countries/$COUNTRY/questions/questions_ab.json"
  # Список файлов сначала в переменную: при `grep -q` в конвейере unzip
  # получает SIGPIPE, а из-за pipefail это выглядит как «не нашли».
  local listing
  listing="$(unzip -l "$archive")"
  if ! printf '%s' "$listing" | grep -q -- "$needle"; then
    echo "СБОРКА БРАКОВАННАЯ: в $archive нет $needle" >&2
    exit 1
  fi
  echo "проверка: контент страны $COUNTRY в артефакте есть"
}

case "$TARGET" in
  aab)
    flutter build appbundle --release \
      --flavor "$COUNTRY" \
      --dart-define=COUNTRY="$COUNTRY" \
      ${NOTIFY_DEFINES[@]+"${NOTIFY_DEFINES[@]}"} \
      ${EXTRA_DEFINES_ARR[@]+"${EXTRA_DEFINES_ARR[@]}"}
    verify_archive "build/app/outputs/bundle/${COUNTRY}Release/app-${COUNTRY}-release.aab"
    echo "AAB: build/app/outputs/bundle/${COUNTRY}Release/app-${COUNTRY}-release.aab"
    ;;
  apk)
    # Универсальный APK (все ABI одним файлом) — для ручной установки на
    # устройство/тестирование.
    flutter build apk --release \
      --flavor "$COUNTRY" \
      --dart-define=COUNTRY="$COUNTRY" \
      ${NOTIFY_DEFINES[@]+"${NOTIFY_DEFINES[@]}"} \
      ${EXTRA_DEFINES_ARR[@]+"${EXTRA_DEFINES_ARR[@]}"}
    verify_archive "build/app/outputs/flutter-apk/app-${COUNTRY}-release.apk"
    echo "APK: build/app/outputs/flutter-apk/app-${COUNTRY}-release.apk"
    ;;
  ipa)
    # iOS (ru.pdd.pddApp): архив + экспорт с
    # destination=upload из ios/ExportOptions.plist — сборка сразу уходит в
    # App Store Connect через аккаунт, в который вошёл Xcode.
    flutter build ipa --release \
      --dart-define=COUNTRY="$COUNTRY" \
      --export-options-plist=ios/ExportOptions.plist \
      ${NOTIFY_DEFINES[@]+"${NOTIFY_DEFINES[@]}"} \
      ${EXTRA_DEFINES_ARR[@]+"${EXTRA_DEFINES_ARR[@]}"}
    echo "IPA: загружено в App Store Connect (build/ios/archive/Runner.xcarchive)"
    ;;
  web)
    flutter build web --release --base-href "${WEB_BASE_HREF:-/}" --no-wasm-dry-run \
      --dart-define=COUNTRY="$COUNTRY" \
      ${NOTIFY_DEFINES[@]+"${NOTIFY_DEFINES[@]}"} \
      ${EXTRA_DEFINES_ARR[@]+"${EXTRA_DEFINES_ARR[@]}"}
    echo "Web: build/web (COUNTRY=$COUNTRY)"
    ;;
  *) echo "unknown target: $TARGET (expected aab|apk|ipa|web)"; exit 1 ;;
esac
