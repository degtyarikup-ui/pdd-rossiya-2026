#!/usr/bin/env bash
# Локальная админка блога pdd-drive.ru.
#   ./scripts/blog_admin.sh
#
# ВАЖНО: админка работает ТОЛЬКО на твоём компьютере (127.0.0.1:8930).
# На сайте pdd-drive.ru её нет и быть не должно: сайт — статика на GitHub Pages,
# а в админке нет паролей, поэтому в интернет её выкладывать нельзя.
# Порядок работы: запустил скрипт → отредактировал → «Опубликовать на сайт».
set -euo pipefail
cd "$(dirname "$0")/.."

URL="http://127.0.0.1:8930/admin"
echo "Админка блога → $URL   (Ctrl-C — остановить)"

# Открыть браузер, когда сервер поднимется (в фоне, чтобы не блокировать запуск).
if command -v open >/dev/null 2>&1; then
  ( for _ in $(seq 1 40); do
      if curl -s -o /dev/null "http://127.0.0.1:8930/api/articles" 2>/dev/null; then
        open "$URL"; break
      fi
      sleep 0.5
    done ) &
fi

exec python3 tools/blog_admin/server.py
