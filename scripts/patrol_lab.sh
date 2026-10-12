#!/usr/bin/env bash
# Локальный тестовый стенд игры «Найди нарушителя»: http://127.0.0.1:8960/
set -euo pipefail
cd "$(dirname "$0")/.."

URL="http://127.0.0.1:8960/"
echo "=========================================================="
echo "🚔 Стенд «Найди нарушителя» → $URL (Ctrl-C — выход)"
echo "=========================================================="

# Попытка открыть браузер в фоне
if command -v xdg-open >/dev/null 2>&1; then
  ( sleep 0.8 && xdg-open "$URL" >/dev/null 2>&1 ) &
elif command -v open >/dev/null 2>&1; then
  ( sleep 0.8 && open "$URL" >/dev/null 2>&1 ) &
fi

exec python3 tools/patrol_lab/server.py
