# 3D-игра «Живой город» — как запустить и где что лежит

Игра — **Godot 4.7.2** (Compatibility), папка `game_godot/`. Старая WebView-игра (Three.js)
удалена; последний коммит с ней — тег `game-webview-final`. Мини-игры «Регулировщик»
(`game_godot/regulator.tscn`, флаг `--regulator`) и «Разрули перекрёсток»
(`game_godot/crossroads.tscn`, флаг `--crossroads`) также работают на Godot.

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
| FFmpeg (`ffmpeg` и `ffprobe`) | подготовка существующей студийной озвучки для Godot |

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
В мини-играх верхняя кнопка сразу возвращает в меню; отдельного окна паузы нет.

## Проверки (headless)

```bash
godot --headless --path game_godot --script res://tests/regulator_check.gd # регулировщик: правила, экономика, UI, рестарты
godot --headless --path game_godot --script res://tests/regulator_performance_check.gd # регулировщик: профили телефона, адаптация, разрешение UI и повторный вход
godot --headless --path game_godot --script res://tests/regulator_atmosphere_check.gd # регулировщик: стабильная погода без лишних обновлений рендера и переходы
godot --headless --path game_godot --script res://tests/crossroads_check.gd # разъезд на перекрёстках: 27 сценариев, ПДД, траектории, UI
godot --headless --path game_godot --script res://tests/crossroads_play_check.gd # все 27 задач: проезд, фокус, камера, таймер, повтор и мультитач
godot --headless --path game_godot --script res://tests/crossroads_camera_check.gd # ограничение zoom и прозрачность только закрывающих обзор зданий; также native
godot --headless --path game_godot --script res://tests/crossroads_routes_check.gd # реальные кузова, полосы, остановка у 2.5 и экранный размер кнопок
godot --headless --path game_godot --script res://tests/crossroads_world_check.gd # все знаки/дубли, переходы, стоп-линии, рельсы, сезонные материалы
godot --path game_godot --script res://tests/crossroads_world_check.gd # дополнительно реальные пиксели скруглений и пандусов
godot --headless --path game_godot --script res://tests/crossroads_ui_check.gd # HUD, диалоги, короткий экран; повторить с -- --text-scale=1.6
godot --headless --path game_godot --script res://tests/mini_game_results_check.gd # общий результат мини-игр: ru/en/kk, малые экраны, текст 1,6
godot --path game_godot --script res://tests/exit_transition_check.gd # реальный fade выхода: неподвижный кадр, покрытие, summary и повторный вход
godot --headless --path game_godot --script res://tests/rules_check.gd      # нарушения: 47 проверок
godot --headless --path game_godot --script res://tests/road_check.gd       # дорожные вопросы: 70 проверок
godot --headless --path game_godot --script res://tests/surface_check.gd    # перекрёстки без дублей дорожного слоя
godot --headless --path game_godot --script res://tests/street_check.gd     # улица: сужение перед перекрёстком, застройка вне проезжей части
godot --headless --path game_godot --script res://tests/building_models_check.gd # дома: бюджет геометрии, габариты, пакетный рендер и сезонные материалы
godot --headless --path game_godot --script res://tests/people_models_check.gd # пешеходы и регулировщик: модели, жесты, шаг и бюджет геометрии
godot --headless --path game_godot --script res://tests/vehicle_models_check.gd # общий транспорт NPC/гаража: меши, сигналы, габариты и бюджет
godot --headless --path game_godot --script res://tests/environment_models_check.gd # деревья/улица: бюджет и исходное размещение всех сцен
godot --headless --path game_godot --script res://tests/collision_check.gd  # столкновения
godot --headless --path game_godot --script res://tests/sign_mount_check.gd # общая стойка и консоль знаков
godot --headless --path game_godot --script res://tests/signals_models_check.gd # знаки/светофоры: формы, состояния, крепления, кеши и бюджет
godot --path game_godot --script res://tests/signals_render_check.gd # реальный фронт/тыл и отдельные трамвайные апертуры
godot --headless --path game_godot --script res://tests/lane_sign_check.gd # конструктор направлений по полосам
godot --headless --path game_godot --script res://tests/free_player_check.gd # 76 проверок свободной позы, 12 углов и подъезда по кольцу
godot --headless --path game_godot --script res://tests/dirt_surface_check.gd # грунт, текстура и удаление старых накладок
godot --headless --path game_godot --script res://tests/human_collision_check.gd # наезд: регулировщик и пешеходы
godot --headless --path game_godot --script res://tests/ghost_check.gd      # призрак улицы
godot --path game_godot --script res://tests/pool_packing_check.gd # пустые экземпляры не рисуются; цвета, прозрачность, индексы чанков и границы пакетов
godot --headless --path game_godot --script res://tests/ambient_transition_check.gd -- --season=autumn # пешеходы, листья и трафик при переходах
godot --path game_godot --script res://tests/ambient_transition_check.gd -- --season=autumn # реальные позы MultiMesh и положение в кадре
godot --headless --path game_godot --script res://tests/lighting_check.gd # свет/тени в том же кадре при поворотах мира, все уровни качества
godot --path game_godot --script res://tests/lighting_render_check.gd # нужен рендер: яркость граней, машина и тени до/после перехода
godot --headless --path game_godot --script res://tests/retained_surface_check.gd # старые улицы и сцены не перекрывают дорогу после цепочки поворотов
godot --headless --path game_godot --script res://tests/retirement_support_check.gd # очистка старых дорог не удаляет опору машины после долгого манёвра
godot --headless --path game_godot --script res://tests/traffic_check.gd    # трафик
godot --headless --path game_godot --script res://tests/ambient_focus_check.gd # чистый кадр вопроса, плавный отвод трафика, объезд парковки и встречный поток
godot --headless --path game_godot --script res://tests/terrain_motion_check.gd # проезд стыков, изменённые тротуары, движение копий и участников по видимой поверхности
godot --headless --path game_godot --script res://tests/participant_motion_check.gd # коллизии и отъезд после стрелки
godot --headless --path game_godot --script res://tests/participant_lifetime_check.gd # наезд: реальное удаление модели через 20 секунд, старые участники и подписи
godot --headless --path game_godot --script res://tests/answer_traffic_check.gd # порядок старта после ответа, ожидание игрока, holdFor и движение после завершения вопроса
godot --headless --path game_godot --script res://tests/answer_traffic_world_check.gd # реальные сцены: проезд игрока, перебазирование мира и отъезд участников
godot --headless --path game_godot --script res://tests/tram_tracks_check.gd # автоматические пути, полный кузов, декорации, проёмы и сохранность исходных сцен
godot --headless --path game_godot --script res://tests/tram_motion_check.gd # трамвай тормозит перед людьми/машинами и остаётся на рельсах
godot --headless --path game_godot --script res://tests/tram_world_check.gd # препятствия мира, сохранённая улица, повернутые ограды и кеш проверок
godot --headless --path game_godot --script res://tests/tram_crossing_check.gd # непрерывный переход через пути, ожидание, габариты и оставшиеся старые рельсы; native — неподвижная поза в реальном рендере
godot --path game_godot --script res://tests/tram_render_check.gd # нужен рендер: реальные локации, въезды, окончания и единый меш покрытия
godot --headless --path game_godot --script res://tests/reviewed_departure_check.gd # продолжение всех отмеченных сцен
godot --headless --path game_godot --script res://tests/ride_endurance_check.gd # 40 переходов по кольцу, стабильная память, завершение только на 20-м ответе
godot --path game_godot --script res://tests/ride_runtime_stress_check.gd -- --stress-scenes=40 --stress-dwell=6 # длительный рендер/обновления; синтетическое перемещение через обычные переходы
godot --path game_godot --script res://tests/ride_runtime_stress_check.gd -- --stress-scenes=40 --stress-dwell=6 --stress-mixed-answers # верные/неверные ответы, таймауты, повторный тап, номера 1–20 и завершение
godot --headless --path game_godot --script res://tests/streaming_check.gd # выбор «В игре», подготовка и пауза
godot --headless --path game_godot --script res://tests/exit_loading_check.gd # выход во время фоновой сборки без потерянных узлов
godot --headless --path game_godot --script res://tests/embedded_io_check.gd # iOS: повторные запуски основной игры и переходы после мини-игр
godot --headless --path game_godot --script res://tests/walking_budget_check.gd # точность тротуаров, ограниченный кеш и бюджет поиска пути пешеходов
godot --headless --path game_godot --script res://tests/actor_visibility_check.gd # участники без dir не вызывают покадровые ошибки проверки видимости
godot --headless --path game_godot --script res://tests/frame_budget_check.gd # подстройка нагрузки телефона без реакции на загрузку и паузу
godot --headless --path game_godot --script res://tests/perf_log_check.gd # температура iOS и синхронные интервалы CPU/кадров
godot --headless --path game_godot --script res://tests/ride_benchmark_check.gd # повторяемый тестовый маршрут без очков и расхода заезда
godot --headless --path game_godot --script res://tests/pause_actor_check.gd # заморозка независимых и физических участников в паузе
godot --headless --path game_godot --script res://tests/shared_pictures_check.gd # общий источник фото Flutter/Godot без копий
godot --headless --path game_godot --script res://tests/game_ui_check.gd # анимации, фото, компактный HUD и окно паузы
godot --headless --path game_godot --script res://tests/controls_layout_check.gd # крупные педали/повороты: экраны 280–640 dp, плотности, системные отступы и мультитач
godot --headless --path game_godot --script res://tests/vehicle_lights_check.gd # штатные линзы, мигание и синхронное процедурное свечение
godot --path game_godot --script res://tests/beacon_render_check.gd # дневная яркость маячков ДПС/спецмашин относительно аварийки, low/high
godot --headless --path game_godot --script res://tests/question_signals_check.gd # намерения игрока/участников, вопрос без задержки, поворотники и пауза
godot --headless --path game_godot --script res://tests/tram_question_signals_check.gd # правые сигналы трамваев 15/13, 28/13, 36/14: линзы, ореолы, ответ, пауза и выключение
godot --headless --path game_godot --script res://tests/actor_hazards_check.gd # постоянная аварийка участников, стоянка, обе стороны, пауза и старые настройки
godot --headless --path game_godot --script res://tests/signal_glow_check.gd # свечение и цвета секций светофора без текстур
godot --headless --path game_godot --script res://tests/ride_pause_check.gd # быстрый старт, цвет, звук, сохранение состояния при паузе
godot --headless --path game_godot --script res://tests/lifecycle_pause_check.gd # системное сворачивание/фокус, достижимая пауза и восстановление управления
godot --headless --path game_godot --script res://tests/exit_continuity_check.gd # все физические выезды, короткие улицы, полный кузов и стыковка следующего вопроса
godot --headless --path game_godot --script res://tests/lane_join_check.gd # подбор по фактическим полосам, въезд в 13/13 и плавные переходы 1+1 ↔ 2+2
godot --path game_godot --resolution 1280x900 --script res://tests/signal_glow_check.gd # нужен широкий кадр: видимое свечение, включая пакетный трафик
godot --path game_godot --script res://tests/building_fade_check.gd # нужен рендер: пачки прозрачных зданий и переиспользование
godot --headless --path game_godot --script res://tests/median_join_check.gd # границы разделительных островов
tools/network/.venv/bin/python tools/network/tests/highway_check.py # фикстуры сквозных трасс и переходов, сохранение, сборка, весь кузов
godot --headless --path game_godot --script res://tests/highway_check.gd # реальные стыки 3+3 и 2+2 по фикстурам предыдущей команды
godot --headless --path game_godot --script res://tests/highway_run_check.gd # цепочка вопросов, переход 90 м, кривой въезд, разделители и кузов
godot --headless --path game_godot --script res://tests/ambient_lane_check.gd # фоновые машины и разделитель на стыке
godot --path game_godot --script res://tests/sound_check.gd # аудио: запуск, выключение, включение и освобождение
godot --path game_godot --script res://tests/occlusion_render_check.gd # нужен рендер: прозрачность зданий
godot --path game_godot --script res://tests/stitch_shader_render_check.gd # нужен рендер: мировая сетка текстур после стыковки
```

Скрипт с ошибкой в headless-режиме **зависает**, а не падает: ставьте таймаут
(`perl -e 'alarm 300; exec @ARGV' godot ...`). После изменения скриптов с `class_name`
выполните `godot --headless --path game_godot --import`.

Известная проблема проверки (14 октября 2026): `signals_models_check.gd` загружает
старую фикстуру `situations/ticket_37_13/light_0.glb`, которой нет в Git.
В чистой копии проверка зависает после ошибки загрузки; её нельзя считать пройденной.

`people_models_check.gd` на 14 октября 2026 имеет три ошибки проверки общего материала
регулировщика (`officer: shared cached material`), воспроизводимые до исправления переходов.
`pause_actor_check.gd` проходит свои семь проверок, но в headless выдаёт ошибку dummy-рендера
`Parameter "material" is null`; она также воспроизводится на исходном коде.

`camera_check.gd` также имеет сбой фикстуры: после первого вопроса очистка оставляет
`question_signal_id`, и второй сценарий `ticket_12_5` не движется. На 14 октября 2026
ошибка воспроизведена с исходным `world.gd` до исправления освещения; тест не вызывает
переход локаций (`_on_finished`). Её нельзя считать успешной проверкой камеры.

Фоновый поток задаётся в `data/world.json`: две машины на кольцо,
`parked_chance: 0.02` для подходящих мест парковки. Перед вопросом резервируется
зона `question_clear_radius: 180` м (для большой сцены — не меньше её границ
с запасом). Обычные машины тормозят перед зоной; уже видимые покидают кадр
своим ходом до запуска таймера. Переиспользование машин происходит за камерой.
Участники самой задачи сохраняются. Припаркованные машины учитываются по
реальным габаритам на всём кольце: NPC заранее объезжает их, пропускает встречный
поток или останавливается, если законного и безопасного места для объезда нет.

Если у игрока или участника задания задан поворот/разворот, нужные поворотники
включаются на остановке одновременно с карточкой, без дополнительного ожидания.
Отсчёт ответа начинается сразу с вопросом; пауза замораживает таймер и мигание.
Направление игрока берётся из `spec.maneuver`, участников — из `signalPlan`
или `config.targetAction`; геометрия маршрута используется только при отсутствии
заданного намерения. Разворот включает левый сигнал. Трамваи также показывают
поворот; в дорожных заданиях учтены заданные сигналы машин и выезд автобуса
с остановки. После манёвра участник выключает сигнал.

Участники начинают движение после нажатия ответа: сначала заданные в
`spec.yieldTo`, остальные — с учётом `waitsForPlayer`, пересечения маршрутов
и `concurrentWith`. Неправильный ответ и объяснение не меняют приоритет игрока.
Уступающие ждут завершения его проезда, затем едут сами; завершение вопроса
и смена системы координат не останавливают оставшихся участников. Продолжение
за учебной стрелкой строится только в памяти по существующей дороге, удаление
модели допускается после её выхода из кадра. Явный `staysPut` из редактора
важнее старых настроек неподвижности шаблона; временные остановки, `holdFor`
и намеренно стоящие участники сохраняются.

На 15 октября 2026 отдельно оставлены для исправления владельцем в редакторе
отсутствующие маршруты: `ticket_14_14/tram_a` и три участника `ticket_27_15`
(`car_1`, `motorcycle_1`, `bus_1`). Игра не подменяет их маршрутами из старых
шаблонов: направления шаблонов могут расходиться с заданием автора.

У `ticket_27_14` выбран проезд прямо, но сохранены только маршруты поворотов.
Пока автор не добавит соответствующий путь в редакторе, обычный заезд временно
пропускает сцену; отметка «В игре» сохраняется. Проверка сети теперь сообщает
об отсутствии пути прямо так же, как об отсутствии поворота.

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

Фотографии билетов — один источник: `assets/countries/ru/images/questions_ab/`.
Редактор читает их напрямую. Godot хранит только соответствие сцены и имени фото
в `questions/index.json`; `PackFiles` читает тот же WebP: на компьютере — из
`assets/`, на Android — через `PddHost.pictureBytes` из Flutter-ресурсов APK,
на iOS — из `Frameworks/App.framework/flutter_assets/`, на сайте — из соседнего
`/app/assets/assets/countries/ru/images/questions_ab/`. В пакет встроенной игры
фотографии не включаются. После замены картинки отдельное копирование не нужно;
уже собранные приложения обновятся при пересборке.

`tools/godot_export/export_question_images.py` обновляет индекс и удаляет старые
копии. Скрипты сборки вызывают его автоматически. Для самостоятельной игры без
Flutter `scripts/godot_dev.sh android|ios` временно создаёт ссылки на исходники
(`--standalone`), включает фотографии в единственный пакет игры и убирает ссылки
после экспорта. Прямой экспорт самостоятельной игры из редактора Godot требует
сначала запустить генератор с `--standalone`; после экспорта — без этого флага.
Ссылки и их `.import` игнорируются Git.

Озвучка вопросов — существующие российские записи `assets/audio/feed/q_<id>.opus`,
без системного синтеза речи. Godot не декодирует Opus, поэтому
`python3 tools/godot_export/export_question_audio.py` один раз преобразует только
используемые вопросы в MP3 в общем каталоге `assets/audio/game_questions/`.
Преобразование повторяется лишь при изменении записи или повреждении результата;
MP3 и локальный манифест не коммитятся. В Git лежит небольшой индекс
`game_godot/questions/audio.json`: исходный ID вопроса, файл и длительность для
каждой сцены. Генератор проверяет дословное совпадение вопроса и порядка ответов
с исходным билетом. На Android записи читает `PddHost.questionAudioBytes`, на iOS
передаётся `--question-audio-dir`, веб читает соседние Flutter-ресурсы; в пакет
встроенной игры записи повторно не входят. Standalone-экспорт временно включает
ссылки на те же MP3 и убирает их после сборки.

`setup_game.sh`, `build.sh`, `build_dev.sh` и скрипты экспорта Godot запускают
генератор автоматически. Перед прямым `flutter build` или запуском Godot из
свежей копии сначала запустите его вручную. Проверки без пересборки записей:
`python3 tools/godot_export/export_question_audio.py --check` и
`python3 -m unittest tools/godot_export/test_question_audio.py`.
Записи есть только на русском; озвучка включается отдельно от звуков игры,
приостанавливается вместе с вопросом и прекращается после ответа.

Строки интерфейса игры берутся из `lib/l10n/*.arb`: `python3 tools/godot_export/export_ui.py`
пересобирает `game_godot/data/ui.json` (ru/en/kk одновременно).

## Приложение (Flutter)

`lib/presentation/screens/game/godot_game.dart` — запуск/продолжение заезда, коллекция для паузы, итоги,
разбор ошибок; канал `pdd/godot_game`. Android — `android/app/src/godot/` (экран игры в процессе
`:game`), iOS — `ios/Runner/PddGodotGame.mm`, web — iframe `/app/godot/`.
Экономика заездов и очков — `docs/game/game-economy-2026-10-10.md`.

## Документы

- `crossroads-refinement-2026-10-15.md` — один формат «Разрули перекрёсток», интерфейс, общая атмосфера и аудит дорожной сцены
- `question-semantic-audit-2026-10-15.md` — смысловые повторы игровых заданий, исключённые сцены и сохранённые различия
- `garage-achievements.md` — общая палитра машин, награды за правильные ответы и перенос старого гаража
- `building-models.md` — модели домов, пересборка и ограничения для слабых телефонов
- `people-models.md` — модели пешеходов и регулировщика, походка и ограничения геометрии
- `vehicle-models.md` — общий источник машин NPC/гаража и лёгкий отдельный транспорт
- `environment-models.md` — лёгкие деревья и уличные объекты с исходными точками установки
- `signs-and-signals.md` — знаки/светофоры, нормативные формы, серый оборот и сохранённые крепления
- `regulator-migration-2026-10-13.md` — паритет регулировщика и удаление WebView
- `regulator-performance-2026-10-15.md` — профили слабых телефонов, автоматический бюджет и контроль нагрузки регулировщика
- `ride-performance-2026-10-14.md` — очистка старых локаций по пути, длительный тест и диагностика dev-сборки
- `road-retirement-2026-10-15.md` — исчезновение дороги под машиной после лимита хранения и защита от застревания на траве
- `participant-lifetime-2026-10-15.md` — нативный вылет после удаления сбитого участника и регрессионная проверка
- `ride-completion-2026-10-15.md` — два штатных заезда, неверная нумерация HUD и оставшийся доступ к удалённому участнику
- `background-pause-2026-10-15.md` — исчезнувшее управление после сворачивания, безопасный показ паузы и продолжение
- `road-exit-continuity-2026-10-15.md` — тупик `ticket_20_6`, все физические выезды и стыки коротких дорог
- `ride-fixes-2026-10-13.md` — загрузка сцен, коллизии, продолжение маршрутов, интерфейс и гараж
- `local-changes-sync-2026-10-14.md` — опубликованные локации и архивы всех локальных stash
- `godot-roadmap.md` — что сделано и что открыто
- `godot-migration.md` — как и почему перешли на Godot
- `game-economy-2026-10-10.md`, `game-covers-2026-10-10.md`, `mini-game*.md` — экономика, обложки, мини-игры

Стыковка билетов по фактическим концам дорог, ширине, полосам и разделителям —
[scene-stitching.md](scene-stitching.md) (устройство и три проверки стыковки).
