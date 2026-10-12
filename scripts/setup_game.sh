#!/usr/bin/env bash
# One-time setup of the Godot game on a fresh clone (game_godot/):
#   ./scripts/setup_game.sh
# Checks Godot 4.7.2 and its export templates, makes the Python environment of the road-network
# tools (tools/network/.venv), imports the Godot project. Everything else is in git.
set -euo pipefail
cd "$(dirname "$0")/.."
WANT="4.7.2"

command -v godot >/dev/null || { echo "Нет godot в PATH. Нужен Godot $WANT (Standard): https://godotengine.org/download"; exit 1; }
HAVE="$(godot --version | cut -d. -f1-3)"
[[ "$HAVE" == "$WANT" ]] || echo "Внимание: Godot $HAVE, а проект на $WANT — файлы .import и .uid могут отличаться."

# Export templates (Android/iOS/Web builds): Godot → Editor → Manage Export Templates.
TPL="$HOME/.local/share/godot/export_templates/$WANT.stable"
[[ -d "$TPL" ]] || TPL="$HOME/Library/Application Support/Godot/export_templates/$WANT.stable"
[[ -d "$TPL" ]] || echo "Нет шаблонов экспорта $WANT: без них не собрать Android/iOS/Web (запуск на компьютере работает)."

# Python of the road-network tools (editor, build.py, check.py, engine_sync.py).
if [[ ! -x tools/network/.venv/bin/python ]]; then
  python3 -m venv tools/network/.venv
fi
tools/network/.venv/bin/python -m pip install -q -r tools/network/requirements.txt
echo "Python-окружение сети: tools/network/.venv"

# Import: textures and models into game_godot/.godot (not in git). The first time takes a minute or two.
godot --headless --path game_godot --import >/dev/null 2>&1 || true
git checkout -- game_godot/scenery 2>/dev/null || true   # an import rewrites uids in the committed .import files
echo "Готово. Запуск: godot --path game_godot   (подробнее — docs/game/README.md)"
