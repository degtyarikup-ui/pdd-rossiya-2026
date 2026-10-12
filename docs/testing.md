# Проверки

Перед каждым коммитом (правило проекта — `CLAUDE.md`):

```bash
flutter analyze                     # без замечаний
flutter test                        # все тесты Flutter
```

По области изменений дополнительно:

| Меняли | Запустить |
| --- | --- |
| Строки `*.arb` | `flutter gen-l10n`, затем `flutter test` |
| Вход / Премиум / оплату | список из `docs/premium/README.md` + `npm run test:security` в `server/install-notifier` |
| Воркер | `cd server/install-notifier && npm test` и нужные `npm run test:*` |
| Игру (`game_godot/`) | тесты Godot из `game_godot/tests/`, см. `docs/game/README.md`; мини-игры (`assets/game/`) — `tools/game_tests/*.cjs` |
| Правила экзамена | `flutter test test/exam_flow_test.dart` |
| Контент ПДД | `python3 tools/ru_content/parse_pdd.py` (падает при сбое нумерации) |

Браузерным тестам нужны Playwright (`NODE_PATH`) и Google Chrome.
