# 3D-ачивки: инструмент

Правила формата — [`docs/application/achievements-3d.md`](../../../docs/application/achievements-3d.md).
Здесь только команды. Всё выполняется из `main/`; результаты — в
`../output/achievements_3d/` (рабочая папка, вне git).

| Файл | Что делает |
|---|---|
| `badge3d.py` | общий набор: материалы, металлы уровней, детали знаков, свет, камера, рендер |
| `scenes/<id>.py` | объект конкретной ачивки: `LEVELS` и `build(kit, level)` |
| `render.py` | рендер одного уровня |
| `post.py` | кадр 90%, растворение стойки, 1024/512 и контрольный `_guide.png` |
| `present.py` | лист приёмки: 4 уровня крупно и в сетке 68 pt |
| `textures/*.py` | печать прав и билетов (PIL) — запустить один раз до рендера `exams` и `tickets` |

```sh
B=/Applications/Blender.app/Contents/MacOS/Blender
T=apps/russia/tools/achievements/3d
O="$PWD/../output/achievements_3d"

# печать для прав и билетов (один раз, кладётся в ~/Library/Caches/pdd-achievements/)
python3 $T/textures/license_print.py && python3 $T/textures/ticket_print.py

# пробный кадр (секунды; первый запуск компилирует ядра Metal несколько минут)
$B -b --factory-startup --python $T/render.py -- --achievement streak --level 4 \
  --out "$O/raw/streak_4_test.png" --res 768 --samples 96

# финальные кадры и постобработка
for L in 1 2 3 4; do
  $B -b --factory-startup --python $T/render.py -- --achievement streak --level $L \
    --out "$O/raw/streak_$L.png"
  python3 $T/post.py "$O/raw/streak_$L.png" "$O/streak_$L"
done
python3 $T/present.py streak "$O" "«Без пропусков»"

# в приложение и в Godot
for L in 1 2 3 4; do cp "$O/streak_${L}_512.png" apps/russia/assets/images/achievements/streak_$L.png; done
(cd apps/russia && python3 tools/godot_export/export_ui.py)
```

`--blend файл.blend` сохраняет сцену, чтобы открыть её в Blender. Путь к
файлу с пробелами брать в кавычки, иначе argparse молча завершит Blender.

Нужны Blender 5.x (Cycles, Metal) и системные шрифты macOS: DIN Condensed Bold
и PTSans.ttc (начертание PT Sans Narrow Bold извлекается в
`~/Library/Caches/pdd-achievements/`).
