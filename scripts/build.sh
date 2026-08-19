#!/usr/bin/env bash
# Сборка приложения для страны: ./scripts/build.sh {ru|by|rs} {aab|web}
#
# Единый код — разные страны. Страна задаётся одновременно:
#  - Android flavor (applicationId, имя приложения, иконка),
#  - --dart-define=COUNTRY (правила экзамена, контент, тексты, язык UI).
set -euo pipefail

COUNTRY="${1:?usage: build.sh ru|by|rs aab|apk|web}"
TARGET="${2:?usage: build.sh ru|by|rs aab|apk|web}"

case "$COUNTRY" in
  ru|by|rs) ;;
  *) echo "unknown country: $COUNTRY (expected ru|by|rs)"; exit 1 ;;
esac

export PATH="$HOME/flutter/bin:$PATH"
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
export PATH="$JAVA_HOME/bin:$PATH"

cd "$(dirname "$0")/.."

# --- Ассеты только своей страны ------------------------------------------
# В pubspec.yaml перечислены страны все сразу (иначе flutter run/тесты не
# найдут контент), а Android-flavor ассеты не фильтрует — без этого шага в
# сборку любой страны попадал бы контент всех: сербский AAB весил 142 МБ, из
# них 80 МБ российских картинок, которые пользователь никогда не увидит.
# Поэтому на время сборки вычищаем из pubspec.yaml чужие страны, а по выходу
# (в т.ч. при ошибке/Ctrl-C) возвращаем файл байт-в-байт.
PUBSPEC_BACKUP="$(mktemp -t pubspec.XXXXXX)"
cp pubspec.yaml "$PUBSPEC_BACKUP"
restore_pubspec() {
  cp "$PUBSPEC_BACKUP" pubspec.yaml
  rm -f "$PUBSPEC_BACKUP"
}
trap restore_pubspec EXIT INT TERM

python3 - "$COUNTRY" <<'PYEOF'
import re, sys

country = sys.argv[1]
lines = open('pubspec.yaml').read().split('\n')
asset_re = re.compile(r'^\s*-\s*assets/countries/(\w+)/')

kept, dropped, mine = [], [], []
for line in lines:
    m = asset_re.match(line)
    if m and m.group(1) != country:
        dropped.append(line.strip())
        continue
    if m:
        mine.append(line.strip())
    kept.append(line)

# Раз уже был случай, когда прерванная сборка оставила pubspec без своих
# стран, и в стор уехал AAB вообще без контента: без ассетов страны собирать
# нечего, падаем сразу.
if not mine:
    sys.exit(f'pubspec.yaml: нет ни одной строки assets/countries/{country}/ '
             '— контент страны не попадёт в сборку. Почини pubspec.yaml.')

open('pubspec.yaml', 'w').write('\n'.join(kept))
print(f'pubspec: assets -> only "{country}" ({len(mine)} entries, dropped {len(dropped)} other-country)')
PYEOF

# Опциональное уведомление о новой установке (Telegram). Параметры берутся из
# переменных окружения и в git не попадают. Если не заданы — фича «спит» (no-op):
#   export INSTALL_NOTIFY_URL=https://pdd-install-notifier.<субдомен>.workers.dev
#   export INSTALL_NOTIFY_SECRET=...   # только если на воркере задан SHARED_SECRET
NOTIFY_DEFINES=()
if [[ -n "${INSTALL_NOTIFY_URL:-}" ]]; then
  NOTIFY_DEFINES+=(--dart-define=INSTALL_NOTIFY_URL="$INSTALL_NOTIFY_URL")
fi
if [[ -n "${INSTALL_NOTIFY_SECRET:-}" ]]; then
  NOTIFY_DEFINES+=(--dart-define=INSTALL_NOTIFY_SECRET="$INSTALL_NOTIFY_SECRET")
fi

# Доп. --dart-define через окружение (напр. тестовая сборка с дебаг-меню:
#   EXTRA_DEFINES="--dart-define=NOTIF_TEST=true" ./scripts/build.sh rs apk ).
EXTRA_DEFINES_ARR=()
if [[ -n "${EXTRA_DEFINES:-}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_DEFINES_ARR=($EXTRA_DEFINES)
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
    # устройство/тестирование. Ассеты уже вычищены под страну выше, так что
    # APK не раздувается контентом чужих стран.
    flutter build apk --release \
      --flavor "$COUNTRY" \
      --dart-define=COUNTRY="$COUNTRY" \
      ${NOTIFY_DEFINES[@]+"${NOTIFY_DEFINES[@]}"} \
      ${EXTRA_DEFINES_ARR[@]+"${EXTRA_DEFINES_ARR[@]}"}
    verify_archive "build/app/outputs/flutter-apk/app-${COUNTRY}-release.apk"
    echo "APK: build/app/outputs/flutter-apk/app-${COUNTRY}-release.apk"
    ;;
  web)
    flutter build web --release --base-href "/" --no-wasm-dry-run \
      --dart-define=COUNTRY="$COUNTRY" \
      ${NOTIFY_DEFINES[@]+"${NOTIFY_DEFINES[@]}"} \
      ${EXTRA_DEFINES_ARR[@]+"${EXTRA_DEFINES_ARR[@]}"}
    echo "Web: build/web (COUNTRY=$COUNTRY)"
    ;;
  *) echo "unknown target: $TARGET (expected aab|web)"; exit 1 ;;
esac
