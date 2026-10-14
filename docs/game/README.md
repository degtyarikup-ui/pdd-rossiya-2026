# 3D-игра «Живой город» — как запустить и где что лежит

Игра — **Godot 4.7.2** (Compatibility), папка `game_godot/`. Старая WebView-игра (Three.js)
удалена; последний коммит с ней — тег `game-webview-final`. Мини-игра «Регулировщик»
также перенесена на Godot (`game_godot/regulator.tscn`, флаг `--regulator`). Мини-игра
«Перекрёсток» остаётся на `assets/game/`.

В git лежит всё для запуска: код, модели, сцены перекрёстков (`game_godot/situations/`,
207 МБ), данные сети и их сборка (`game_godot/network/`, `network/build/`), строки интерфейса
(`data/ui.json`). Не в git только то, что строится само: кэш импорта `game_godot/.godot/`,
движок и пакет для Android/iOS (`android/godot/`, `ios/Godot/`), превью редактора
(`network/preview/`).

## Что поставить (один раз)

| Что | Зачем |
|---|---|
| Godot **4.7.2** Standard, команда `godot` в PATH | запуск и тесты |
| Шаблоны экспорта 4.7.2 (Godot → Editor → Manage Export Templates) | сборка Android / iOS / Web |
| Flutter (`~/flutter/bin`) + JDK 17 + Android SDK | сборка приложения |
| Python 3 | редактор и сборка сети |

```bash
./scripts/setup_game.sh      # проверит Godot, поставит Python-пакеты сети, импортирует проект
```

Для тестовой сборки Android (`-Pdev`) магазинный ключ не нужен: без
`android/key.properties` APK подписывается локальным debug-ключом.
Ключи `android/key.properties` и `android/upload-keystore.jks` нужны для
магазинных сборок. Для связи с сервером нужен `secrets/install_notify_secret.txt`
(эти локальные файлы не в git: возьмите у владельца отдельно).
Подготовка SDK, исправление загрузки зависимостей и сопряжение телефона —
[сборка Android на другом компьютере](../build/android.md).

## Запуск на компьютере

```bash
godot --path game_godot                          # окно: игра с первого перекрёстка
godot --path game_godot -- --situation=ticket_10_13 --auto --near   # один перекрёсток, автопилот
```

Флаги — в `game_godot/README.md`. Игра стартует сразу; выбор машины/цвета, звук и выход доступны в окне паузы.
Приложение передаёт коллекцию и настройки через `--ride-options=<JSON>`.

## Проверки (headless)

```bash
godot --headless --path game_godot --script res://tests/regulator_check.gd # регулировщик: правила, экономика, UI, рестарты
godot --headless --path game_godot --script res://tests/rules_check.gd      # нарушения: 47 проверок
godot --headless --path game_godot --script res://tests/road_check.gd       # дорожные вопросы: 70 проверок
godot --headless --path game_godot --script res://tests/surface_check.gd    # перекрёстки без дублей дорожного слоя
godot --headless --path game_godot --script res://tests/street_check.gd     # улица: сужение перед перекрёстком, застройка вне проезжей части
godot --headless --path game_godot --script res://tests/building_models_check.gd # дома: бюджет геометрии, габариты, пакетный рендер и сезонные материалы
godot --headless --path game_godot --script res://tests/people_models_check.gd # пешеходы и регулировщик: модели, жесты, шаг и бюджет геометрии
godot --headless --path game_godot --script res://tests/collision_check.gd  # столкновения
godot --headless --path game_godot --script res://tests/sign_mount_check.gd # общая стойка и консоль знаков
godot --headless --path game_godot --script res://tests/lane_sign_check.gd # конструктор направлений по полосам
godot --headless --path game_godot --script res://tests/free_player_check.gd # 76 проверок свободной позы, 12 углов и подъезда по кольцу
godot --headless --path game_godot --script res://tests/dirt_surface_check.gd # грунт, текстура и удаление старых накладок
godot --headless --path game_godot --script res://tests/human_collision_check.gd # наезд: регулировщик и пешеходы
godot --headless --path game_godot --script res://tests/ghost_check.gd      # призрак улицы
godot --headless --path game_godot --script res://tests/traffic_check.gd    # трафик
godot --headless --path game_godot --script res://tests/ambient_focus_check.gd # чистый кадр вопроса, плавный отвод трафика, объезд парковки и встречный поток
godot --headless --path game_godot --script res://tests/terrain_motion_check.gd # проезд стыков, изменённые тротуары, движение копий и участников по видимой поверхности
godot --headless --path game_godot --script res://tests/participant_motion_check.gd # коллизии и отъезд после стрелки
godot --headless --path game_godot --script res://tests/reviewed_departure_check.gd # продолжение всех отмеченных сцен
godot --headless --path game_godot --script res://tests/streaming_check.gd # выбор «В игре», подготовка и пауза
godot --headless --path game_godot --script res://tests/exit_loading_check.gd # выход во время фоновой сборки без потерянных узлов
godot --headless --path game_godot --script res://tests/pause_actor_check.gd # заморозка независимых и физических участников в паузе
godot --headless --path game_godot --script res://tests/game_ui_check.gd # анимации, фото, компактный HUD и окно паузы
godot --headless --path game_godot --script res://tests/vehicle_lights_check.gd # штатные линзы, мигание и синхронное процедурное свечение
godot --headless --path game_godot --script res://tests/signal_glow_check.gd # свечение и цвета секций светофора без текстур
godot --headless --path game_godot --script res://tests/ride_pause_check.gd # быстрый старт, цвет, звук, сохранение состояния при паузе
godot --path game_godot --resolution 1280x900 --script res://tests/signal_glow_check.gd # нужен широкий кадр: видимое свечение, включая пакетный трафик
godot --path game_godot --script res://tests/building_fade_check.gd # нужен рендер: пачки прозрачных зданий и переиспользование
godot --headless --path game_godot --script res://tests/median_join_check.gd # границы разделительных островов
godot --headless --path game_godot --script res://tests/ambient_lane_check.gd # фоновые машины и разделитель на стыке
godot --path game_godot --script res://tests/sound_check.gd # аудио: запуск, выключение, включение и освобождение
godot --path game_godot --script res://tests/occlusion_render_check.gd # нужен рендер: прозрачность зданий
godot --path game_godot --script res://tests/stitch_shader_render_check.gd # нужен рендер: мировая сетка текстур после стыковки
```

Скрипт с ошибкой в headless-режиме **зависает**, а не падает: ставьте таймаут
(`perl -e 'alarm 300; exec @ARGV' godot ...`). После изменения скриптов с `class_name`
выполните `godot --headless --path game_godot --import`.

Фоновый поток задаётся в `data/world.json`: две машины на кольцо,
`parked_chance: 0.02` для подходящих мест парковки. Перед вопросом резервируется
зона `question_clear_radius: 180` м (для большой сцены — не меньше её границ
с запасом). Обычные машины тормозят перед зоной; уже видимые покидают кадр
своим ходом до запуска таймера. Переиспользование машин происходит за камерой.
Участники самой задачи сохраняются. Припаркованные машины учитываются по
реальным габаритам на всём кольце: NPC заранее объезжает их, пропускает встречный
поток или останавливается, если законного и безопасного места для объезда нет.

## Сборка и установка

```bash
./scripts/godot_android_assets.sh     # движок + файлы игры → android/godot/ (не в git)
./scripts/build_dev.sh                # тестовый APK без установки на телефон
./scripts/install_dev.sh --build      # тестовый APK ru.pdd.pdd_app.dev на телефон по Wi-Fi
./scripts/godot_ios_assets.sh         # то же для iOS (ios/Godot/)
./scripts/godot_dev.sh web            # игра для сайта: build/web/godot/
```

Без `android/godot/` приложение собирается, но в разделе «Игры» игра недоступна
(`GodotGame.available()` = false, показывается сообщение). Подробности — `game_godot/README.md` и
комментарии в начале скриптов.

При тайм-аутах загрузки Google Maven: `./scripts/build_dev.sh --download-fallback`
или `./scripts/install_dev.sh --build --download-fallback`. Промежуточный Godot
APK в `godot_android_assets.sh` экспортируется без подписи: из него берутся
только ресурсы, upload-keystore для этого не требуется.

## Данные: откуда что берётся

```
tools/network/editor  ──►  game_godot/network/<id>.json      (сеть дорог: источник правды)
tools/network/build.py ─►  game_godot/network/build/<id>.json (поверхности, бордюры, проезжая часть)
tools/network/engine_sync.py ► game_godot/situations/<id>/scene.json (то, что читает игра)
```

Редактор сцен (конструктор дорог, тест, текстуры) — `docs/game/editor.md`.

После правки сети (редактор: `./scripts/network_editor.sh` → http://127.0.0.1:8950/, он
сам вызывает сборку при сохранении) закоммитьте и `network/*.json`, и `network/build/`,
и `situations/*/scene.json`. Проверка сети: `tools/network/.venv/bin/python tools/network/check.py`
(9 известных ошибок «маршрут вне дороги» в неизменённых сценах на 14 октября 2026;
в новых правках ошибки появляться не должны).

Строки интерфейса игры берутся из `lib/l10n/*.arb`: `python3 tools/godot_export/export_ui.py`
пересобирает `game_godot/data/ui.json` (ru/en/kk одновременно).

## Приложение (Flutter)

`lib/presentation/screens/game/godot_game.dart` — запуск/продолжение заезда, коллекция для паузы, итоги,
разбор ошибок; канал `pdd/godot_game`. Android — `android/app/src/godot/` (экран игры в процессе
`:game`), iOS — `ios/Runner/PddGodotGame.mm`, web — iframe `/app/godot/`.
Экономика заездов и очков — `docs/game/game-economy-2026-10-10.md`.

## Документы

- `building-models.md` — модели домов, пересборка и ограничения для слабых телефонов
- `people-models.md` — модели пешеходов и регулировщика, походка и ограничения геометрии
- `regulator-migration-2026-10-13.md` — паритет регулировщика и удаление WebView
- `ride-fixes-2026-10-13.md` — загрузка сцен, коллизии, продолжение маршрутов, интерфейс и гараж
- `local-changes-sync-2026-10-14.md` — опубликованные локации и архивы всех локальных stash
- `godot-roadmap.md` — что сделано и что открыто
- `godot-migration.md` — как и почему перешли на Godot
- `game-economy-2026-10-10.md`, `game-covers-2026-10-10.md`, `mini-game*.md` — экономика, обложки, мини-игры

Стыковка билетов по фактическим концам дорог, ширине, полосам и разделителям —
[scene-stitching.md](scene-stitching.md) (устройство и три проверки стыковки).
