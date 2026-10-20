# Проверки

Перед каждым коммитом (правило проекта — `CLAUDE.md`):

```bash
flutter analyze                     # без замечаний
flutter test                        # все тесты Flutter
```

По области изменений дополнительно:

| Меняли | Запустить |
| --- | --- |
| Android-скрипты сборки / загрузки | `python3 -m unittest discover -s tools/android_build -p 'test_*.py'`, `bash -n scripts/*.sh`, dev APK с подготовленным Godot через `scripts/build_dev.sh` |
| Строки `*.arb` | `flutter gen-l10n`, затем `flutter test` |
| Вход / Премиум / оплату | список из `docs/premium/README.md` + `npm run test:security` в `server/install-notifier` |
| Экономику админки | `npm run test:economy`, `npm run test:economy:ui` из `server/install-notifier/` (Playwright + Chrome, см. `docs/admin/README.md`) |
| Воркер | `cd server/install-notifier && npm test` и нужные `npm run test:*` |
| Игру (`game_godot/`) | тесты Godot из `game_godot/tests/`, см. `docs/game/README.md`; мини-игры (`assets/game/`) — `tools/game_tests/*.cjs` |
| Общие студийные записи Flutter/Godot | `python3 -m unittest tools/godot_export/test_question_audio.py`, `python3 tools/godot_export/export_question_audio.py --check` |
| Правила экзамена | `flutter test test/exam_flow_test.dart` |
| Контент ПДД | `python3 tools/ru_content/parse_pdd.py` (падает при сбое нумерации) |

Браузерным тестам нужны Playwright (`NODE_PATH`) и Google Chrome.

## Рилсы на перекрёстках

Сохранённый шаблон и команды — [стандарт](video/reels_3d.md). После изменения
сцены выполнить `build.py init`, `validate`, `preview`; после изменения монтажа
проверить полный `finish` и `check`. Исходники Python: `python3 -m compileall -q
tools/game_reels/crossroads_reel`. Рендер должен работать через Forward+, даже
если проект игры по умолчанию использует Compatibility. Временные результаты
держать в `output/` или `scratch/`, после проверки опубликованного выпуска
сохранять текстовый рецепт и удалять медиа по запросу владельца.
