#!/bin/bash
# Стенд игры: сцены против билетов, езда с клавиатуры, редактор знаков и декора.
cd "$(dirname "$0")/.." && exec python3 tools/game_lab/server.py
