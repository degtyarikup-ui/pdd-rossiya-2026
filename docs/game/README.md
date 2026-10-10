# 3D-игра «Живой город» — карта

Игра — Three.js в WebView. Flutter-обёртка: `lib/presentation/screens/game/`
(мост событий — `game_controller.dart`, `game_screen.dart`).

## Файлы движка (`assets/game/`)

| Файл | Что |
| --- | --- |
| `game.js` | Движок: мир, дороги, перекрёстки, физика, камера, мост во Flutter |
| `junction-situations.js` | Перекрёстки из билетов (геометрия, участники, знаки) |
| `scenario-routes.js` | Проверенные маршруты и правки сцен по билетам (`overrides`) |
| `road-situations.js` | Дорожные вопросы на прямых участках |
| `scene-edits.js` | Ручные правки стенда — **генерируется стендом, руками не править** |
| `model-edits.js` | Правки моделей из мастерской стенда (генерируется) |
| `vehicles.js`, `vehicle-materials.js` | Машина игрока и транспорт |
| `road-materials.js` | Текстуры асфальта, тротуаров, травы, фасадов |
| `street-models.js` | Пешеходы, фонари |
| `sign-textures.js` | Текстуры знаков (большой файл с base64) |
| `seasons.js` | Палитры сезонов, листопад |
| `crossroads.js`, `traffic-controller*.js` | Мини-игры |
| `ambient-audio.js` | Звук мини-игр (WebAudio, без файлов): фон улицы, мотор, трамвай, сирена, удар; включается настройкой «Звук» (`setSoundEnabled` / `TrafficControllerGame.setSound`) |

## Соглашения движка

- Фабрики дорог строят в координатах «X = правая рука водителя»;
  `registerRoadSegment` один раз зеркалирует позиции детей. Запечённая в
  геометрию разметка/полигоны **не** зеркалируются — держать их симметричными
  или задавать в мировых X.
- Проезжая часть — меши с `userData.surface = 'road'` (непрямоугольные — с
  `containsRoad`), непроезжие острова — `userData.noRoad`. Машина физически не
  покидает дорогу.
- Тяжёлые декорации строятся генератором через `enqueueScenery` (по шагам,
  бюджет ~3 мс на кадр); повторяющиеся мелочи сливаются `mergeStatic`.
- После поворота мир «перебазируется» (`finishManeuver`, `maybeReverseWorld`):
  игрок всегда едет по +Z.
- Тупик (знак 6.8.x): `buildDeadEndSegment`, `deadEndAhead()`. За закрытым
  концом ничего не строится. Ситуация включает его полем `deadEnd: 'right'`.

## Стенд и проверки

```bash
./scripts/game_lab.sh                    # http://127.0.0.1:8940/
NODE_PATH=<playwright> node tools/game_tests/game-deadend-test.cjs
```

Тесты в `tools/game_tests/` ждут сервер: большинство — статический сервер
корня репо на :8938 (`python3 -m http.server 8938`), лабораторные — стенд
(`GAME_LAB_PORT=8941 python3 tools/game_lab/server.py`). Порт задаётся
`GAME_URL` / `GAME_LAB_URL`. Playwright и Chrome — локально (`NODE_PATH`).

Известно на 2026-10-10: `game-engine-test` (стрелки маршрута) и
`game-final-driving-test` (билет 31·14) падают и на прежнем коде.

## Документы

- `game-implementation.md` — общее устройство и история
- `game-scenario-audit.md` — сверка сцен с билетами
- `game-review-fixes.md`, `game-texture-passes.md`, `game-streaming-and-trams.md`,
  `game-city-polish-2026-10-10.md`, `game-economy-2026-10-10.md` — проходы доработок
- `mini-games-pdd-audit.md`, `mini-game-covers.md` — мини-игры
- `tools/game_lab/README.md` — стенд, `tools/game_reels/README.md` — ролики
