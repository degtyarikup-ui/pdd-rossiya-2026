#!/bin/bash
# Ролик «Успей узнать знак» для Shorts/Reels/TikTok.
#
#   ./scripts/make_reel.sh                          # список категорий и остаток знаков
#   ./scripts/make_reel.sh "Запрещающие знаки"      # собрать выпуск
#   ./scripts/make_reel.sh "Запрещающие знаки" --voice Rasalgethi --count 5
#
# Готовый mp4 — в assets/videos/signs_reel/.
set -euo pipefail

cd "$(dirname "$0")/.."

if [ $# -eq 0 ]; then
  exec /usr/bin/python3 -m tools.signs_reel.build --list
fi

CATEGORY="$1"
shift
exec /usr/bin/python3 -m tools.signs_reel.build --category "$CATEGORY" "$@"
