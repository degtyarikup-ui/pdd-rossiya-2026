# 3D-игра «Живой город» — как запустить и где что лежит

Игра — **Godot 4.7.2** (Compatibility), папка `game_godot/`. Старая WebView-игра (Three.js)
удалена; последний коммит с ней — тег `game-webview-final`. Мини-игры «Регулировщик»
(`game_godot/regulator.tscn`, флаг `--regulator`) и «Разрули перекрёсток»
(`game_godot/crossroads.tscn`, флаг `--crossroads`) также работают на Godot.

## «Парковка»

`game_godot/parking.tscn`, флаг `--parking` (`GodotGame.playParking`, рекорд —
`parkingProgressProvider`, ключ `parking_progress`, синхронизируется как `miniGames.parking`).
Пять уровней (`scripts/parking_levels.gd`): передом в карман, задом в карман, «ёлочка»,
параллельная у бордюра и «Где можно встать?» — четыре свободных места, разрешено одно
(остальные: ближе 5 м к перекрёстку, знак 3.27, ближе 15 м к остановке 5.16 / 1.17).

- Управление — педали и стрелки города (`scripts/controls.gd`) плюс переключатель D/R над
  стрелками (`scripts/parking_ui.gd`); на клавиатуре R/E/Shift.
- Путь в место нарисован на асфальте полосой ширины машины (синий — вперёд, оранжевый —
  назад), шевроны бегут в сторону движения, круг с буквой — где менять передачу, кнопка D/R
  пульсирует, когда нужна другая. Путь строится от финальной позы: машина «выезжает» из
  места коротким сценарием, путь — этот выезд задом наперёд, поэтому он всегда заканчивается
  точно в месте для любой машины гаража (база колёс меряется по модели).
- Касание машины или бордюра — минус жизнь; на уровне с правилами пути нет, он появляется
  после ошибки. Очки: 60 + до 40 за точность − 15 за касание на уровне.
- Отладка: `-- --parking --level=0..4 --auto --shot=<png> --shot-delay=<с>`.

Проверка: `godot --headless --path game_godot --script res://tests/parking_check.gd` — путь каждого
уровня свободен и заканчивается в месте для всех 7 моделей, единственное верное место на
уровне правил, автопилот паркуется в реальной сцене, итог для приложения.

В git лежит всё для запуска: код, модели, сцены перекрёстков (`game_godot/situations/`,
207 МБ), данные сети и их сборка (`game_godot/network/`, `network/build/`), строки интерфейса
(`data/ui.json`). Не в git только то, что строится само: кэш импорта `game_godot/.godot/`,
движок и пакет для Android/iOS (`android/godot/`, `ios/Godot/`), превью редактора
(`network/preview/`).

## Общий экран завершения

Все три игры используют `scripts/mini_game_results.gd`: непрозрачный полноэкранный
результат на Onest и AppColors: город показывает выбранную модель/краску из гаража,
регулировщик — собственную 3D-модель инспектора, перекрёстки — официальные 2.1 и 8.13
(главная дорога с табличкой её направления). У машины короткий подъезд, у эмблем —
плавное появление и лёгкое движение вверх. Остальная композиция общая:
золотая плашка очков, две метрики и закреплённые нижние действия. Новые игры подключают
этот же компонент и передают свои метрики. На коротком экране прокручивается середина;
крестик и повтор остаются доступны, учитываются safe area и масштаб текста.

Счёт очков и числитель верных ответов растут с нуля за 0,56 с; знаменатель остаётся
неподвижным. Город передаёт дистанцию через `set_distance()` — она растёт одновременно,
с локализованной единицей и десятичной запятой в ru/kk. Ширина плашки очков заранее
резервируется под цифры, чтобы она не дёргалась. Подъезд машины с вращением колёс и
доворотом занимает 0,82 с, за ней остаётся мягкое двумерное свечение. Лучи чуть ярче,
центрируются по реальной плашке даже при прокрутке и совершают оборот за минуту.
Кнопки сжимаются до 97% за 70 мс и возвращаются за 180 мс; есть состояния наведения,
нажатия и клавиатурного фокуса, короткая вибрация по общей настройке. Скрытие экрана
останавливает анимации и сбрасывает кнопки; новый показ отменяет прежние счётчики.
Скругление 12 dp задано для всех шести состояний кнопки, включая `hover_pressed`;
фокус рисует прозрачную рамку. Крестик всегда 48 × 48 dp, не растягивается вместе
с заголовком или размером текста и при нажатии масштабируется равномерно. На широких коротких экранах кнопки компактнее и идут
в две колонки, на узких при крупном шрифте — в одну. Проверка движения также проверяет
реальные пиксели угла нажатой кнопки, отмену тапа и завершение рендера 3D-превью.

После анимации SubViewport машины перестаёт обновляться; камера скрытого мира не
рисует геометрию, дорожный звук приостановлен. «Живой город» показывает верные ответы
и километры, мини-игры — верные ответы и лучшую серию. При отсутствии предыдущего
рекорда подписи нет; превышение существующего рекорда показывает только «Новый рекорд».

Повтор запускается внутри движка. «Живой город» сохраняет выбранную машину, цвет,
историю вопросов и открытые награды, начинает новые 10 вопросов и учитывает остаток
попыток. Ноль попыток блокирует повтор. `city_runs` в итогах хранит завершённые заезды
посещения, верхний уровень — последний заезд, включая незаконченный. Flutter сохраняет
их последовательно, учитывает возобновление, очки и ответы гаража и не показывает второй
диалог (`native_result`). iOS сбрасывает состояние посещения при новом запросе приложения.
Фоновые задачи подготовки дороги отменяются при перезапуске сцены.

Крестик возвращает в приложение. Рейтинг недели внутри игр не открывается: он есть
только во вкладке «Игры» приложения (`game_leaderboard_sheet.dart`). Там сразу показан
сохранённый рейтинг, свежий подгружается с тонкой полоской обновления; без связи —
плашка «Нет связи. Показан рейтинг на …» с повтором и «потяни, чтобы обновить».
Значок с кубком показывает очки недели: сохранённые сразу, 0 при отсутствии очков или входа,
без прочерков. Игрок без очков видит свою строку с 0 и подсказкой, без входа — приглашение войти.

У городской игры в ряду действий осталась только кнопка «Ошибки»; у мини-игр ряд скрыт.

В городе разбор ошибок использует существующий экран приложения. Стойка пары знаков
на результате перекрёстков проходит за знаками и заканчивается под непрозрачной плашкой
очков; её положение учитывает прокрутку, масштаб UI и высоту окна.

Проверки: `tests/result_motion_check.gd`, `tests/city_results_check.gd`, `tests/mini_game_results_check.gd` (также
`-- --text-scale=1.6`), `tests/reward_toast_check.gd`, `tests/ui_theme_check.gd`,
`test/godot_garage_bridge_test.dart`.

## Темп мини-игр

В «Перекрёстке» движение всех участников ускорено вдвое: транспорт сохраняет
траектории и остановку у 2.5, пешеходы пересекают зебру со скоростью воспроизведения
3,6 м/с. Следующего ожидающего участника можно выбрать сразу после предыдущего;
проверка приоритета учитывает только ещё не отправленных. Повторный тап по уже
едущему участнику не выбирает его снова. Таймер не пополняется ни за решение,
ни при появлении сложной задачи; сложность даёт только ×3 очков.

Пешеходы регулировщика используют общий shader походки `Models.walker_gait`: фаза
шага следует пройденному расстоянию, руки/ноги движутся с полной амплитудой, пауза
останавливает и перемещение, и шаг. Проверки: `crossroads_play_check.gd`,
`crossroads_interaction_check.gd`, `crossroads_routes_check.gd`, `regulator_walk_check.gd`.

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

Окно паузы (`scripts/ride_pause.gd`): заголовок по центру и крестик 48 dp; карусель машин —
выбранная крупно в центре, соседи меньше и бледнее по краям (по кругу от трёх машин,
у двух — без круга, с пружиной на краю). Свайп/перетаскивание доводит до ближайшей машины
(флик — ровно на одну), тап по соседу или ←/→ катит её в центр за 0,34 с с доворотом кузова;
каждая машина — своё 3D-превью, перерисовывается только во время движения. Свотчи
квадратные (12 dp), до 6 в ряд, 7–8 цветов — двумя ровными рядами; смена цвета плавно
перекрашивает кузов. Пилюли «Звуки»/«Озвучка» (вкл. — `accent_light` + синий, выкл. — серые)
встают в столбик, если крупный текст не помещается. «Продолжить заезд» — синяя, «Выйти» —
`red_light` с красным текстом. Нажатия сжимают элементы, переключения дают короткую вибрацию.
Приложение передаёт коллекцию и настройки через `--ride-options=<JSON>`.
В мини-играх верхняя кнопка сразу возвращает в меню; отдельного окна паузы нет.

## Проверки (headless)

```bash
godot --headless --path game_godot --script res://tests/regulator_check.gd # регулировщик: правила, экономика, UI, рестарты
godot --headless --path game_godot --script res://tests/regulator_performance_check.gd # регулировщик: профили телефона, адаптация, разрешение UI и повторный вход
godot --headless --path game_godot --script res://tests/regulator_atmosphere_check.gd # регулировщик: стабильная погода без лишних обновлений рендера и переходы
godot --headless --path game_godot --script res://tests/crossroads_check.gd # разъезд на перекрёстках: 50 сценариев (6 категорий), режимы Блиц и Тренировка, ПДД, траектории, UI
godot --headless --path game_godot --script res://tests/crossroads_play_check.gd # все 50 задач: проезд, фокус, камера, таймер, повтор и мультитач
godot --headless --path game_godot --script res://tests/crossroads_camera_check.gd # ограничение zoom и прозрачность только закрывающих обзор зданий; также native
godot --headless --path game_godot --script res://tests/crossroads_routes_check.gd # реальные кузова, полосы, остановка у 2.5 и экранный размер кнопок
godot --headless --path game_godot --script res://tests/crossroads_world_check.gd # все знаки/дубли, переходы, стоп-линии, рельсы, сезонные материалы
godot --path game_godot --script res://tests/crossroads_world_check.gd # дополнительно реальные пиксели скруглений и пандусов
godot --headless --path game_godot --script res://tests/crossroads_ui_check.gd # HUD, диалоги, короткий экран; повторить с -- --text-scale=1.6
godot --headless --path game_godot --script res://tests/crossroads_layout_check.gd # здания не пересекаются друг с другом, здания и деревья не стоят на дорогах и тротуарах (все сценарии и сезоны)
godot --headless --path game_godot --script res://tests/mini_game_results_check.gd # общий результат мини-игр: ru/en/kk, малые экраны, текст 1,6
godot --path game_godot --script res://tests/exit_transition_check.gd # реальный fade выхода: неподвижный кадр, покрытие, summary и повторный вход
godot --path game_godot --script res://tests/result_motion_check.gd # реальная анимация результата, локали, стабильная геометрия и повторные заезды
godot --path game_godot --script res://tests/regulator_walk_check.gd # точные MultiMesh-данные походки всех пешеходов; headless отдельно проверяет физическое состояние
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
godot --headless --path game_godot --script res://tests/question_brake_check.gd -- --situation=ticket_29_13 --mute # торможение перед вопросом: коротко, за ~30 м (также ticket_29_16)
godot --headless --path game_godot --script res://tests/dirt_surface_check.gd # грунт, текстура, ровный край обочины, стык с асфальтом без «ушей»
godot --headless --path game_godot --script res://tests/human_collision_check.gd # наезд: регулировщик и пешеходы
godot --headless --path game_godot --script res://tests/ghost_check.gd      # призрак улицы
godot --path game_godot --script res://tests/pool_packing_check.gd # пустые экземпляры не рисуются; цвета, прозрачность, индексы чанков и границы пакетов
godot --path game_godot --script res://tests/pool_batch_check.gd # одна упаковка нескольких чанков, вложенность, сохранение прозрачности
godot --path game_godot --script res://tests/street_batch_check.gd # точное совпадение дороги, декораций и парковочных коллизий с последовательной сборкой
godot --path game_godot --script res://tests/street_layout_reuse_check.gd # повторное использование декораций при изменении UV, парковка и прозрачность
godot --path game_godot --script res://tests/ground_map_cache_check.gd # карта поверхности сохраняется только при неизменном меше
godot --path game_godot --script res://tests/question_warmup_check.gd # прогрев шрифтов без запуска вопроса; ru/en/kk, размеры и пиксели UI
godot --path game_godot --script res://tests/street_profile_cache_check.gd # кеш профиля ограничен чанком; атрибуты дороги, ширина, декорации и парковка совпадают с исходным расчётом
godot --headless --path game_godot --script res://tests/ambient_trail_motion_check.gd # временно остановленная фоновая машина продолжает движение после перехода, препятствия сохраняются
godot --headless --path game_godot --script res://tests/ambient_transition_check.gd -- --season=autumn # пешеходы, листья и трафик при переходах
godot --path game_godot --script res://tests/ambient_transition_check.gd -- --season=autumn # реальные позы MultiMesh и положение в кадре
godot --headless --path game_godot --script res://tests/lighting_check.gd # свет/тени в том же кадре при поворотах мира, все уровни качества
godot --path game_godot --script res://tests/lighting_render_check.gd # нужен рендер: яркость граней, машина и тени до/после перехода
godot --headless --path game_godot --script res://tests/mesh_clip_check.gd # обрезка геометрии: исходный алгоритм, атрибуты, границы и быстрые повторные проходы
godot --headless --path game_godot --script res://tests/retained_surface_check.gd # старые улицы и сцены не перекрывают дорогу после цепочки поворотов
godot --headless --path game_godot --script res://tests/retirement_support_check.gd # очистка старых дорог не удаляет опору машины после долгого манёвра
godot --headless --path game_godot --script res://tests/traffic_check.gd    # трафик
godot --headless --path game_godot --script res://tests/ambient_focus_check.gd # чистый кадр вопроса, плавный отвод трафика, объезд парковки и встречный поток
godot --headless --path game_godot --script res://tests/terrain_motion_check.gd # проезд стыков, изменённые тротуары, движение копий и участников по видимой поверхности
godot --headless --path game_godot --script res://tests/participant_motion_check.gd # коллизии и отъезд после стрелки
godot --headless --path game_godot --script res://tests/cyclist_crossing_check.gd # 21·8: велосипедист пересекает въезд по заданному пути, продолжение проверяет поверхность
godot --headless --path game_godot --script res://tests/participant_lifetime_check.gd # наезд: реальное удаление модели через 20 секунд, старые участники и подписи
godot --headless --path game_godot --script res://tests/answer_traffic_check.gd # порядок старта после ответа, ожидание игрока, holdFor и движение после завершения вопроса
godot --headless --path game_godot --script res://tests/answer_traffic_world_check.gd # реальные сцены: проезд игрока, перебазирование мира и отъезд участников
godot --headless --path game_godot --script res://tests/officer_answer_check.gd # 31·13: смена жеста и ориентации регулировщика сразу после ответа
godot --headless --path game_godot --script res://tests/legacy_sleepers_check.gd # все GLB: удаление старых деревянных шпал без изменения исходных мешей
godot --headless --path game_godot --script res://tests/tram_tracks_check.gd # автоматические пути, полный кузов, декорации, проёмы и сохранность исходных сцен
godot --headless --path game_godot --script res://tests/tram_motion_check.gd # трамвай тормозит перед людьми/машинами и остаётся на рельсах
godot --headless --path game_godot --script res://tests/tram_world_check.gd # препятствия мира, сохранённая улица, повернутые ограды и кеш проверок
godot --headless --path game_godot --script res://tests/tram_crossing_check.gd # непрерывный переход через пути, ожидание, габариты и оставшиеся старые рельсы; native — неподвижная поза в реальном рендере
godot --path game_godot --script res://tests/tram_render_check.gd # нужен рендер: реальные локации, въезды, окончания и единый меш покрытия
godot --headless --path game_godot --script res://tests/reviewed_departure_check.gd # продолжение всех отмеченных сцен
godot --headless --path game_godot --script res://tests/ride_endurance_check.gd # 40 переходов по кольцу и стабильная память
godot --headless --path game_godot --script res://tests/ride_completion_check.gd # счётчик ответов, завершение на 20-м ответе, ошибка/таймаут и кнопка завершения
godot --path game_godot --script res://tests/ride_runtime_stress_check.gd -- --stress-scenes=40 --stress-dwell=6 # длительный рендер/обновления; синтетическое перемещение через обычные переходы
godot --path game_godot --script res://tests/ride_runtime_stress_check.gd -- --stress-scenes=40 --stress-dwell=6 --stress-mixed-answers # верные/неверные ответы, таймауты, повторный тап, номера 1–20 и завершение
godot --headless --path game_godot --script res://tests/question_streaming_check.gd # задержка/ошибка загрузки: ожидание у стыка и следующий вопрос
godot --headless --path game_godot --script res://tests/departure_progress_check.gd # наклонный выезд, разворот, задний ход и следующий вопрос
godot --headless --path game_godot --script res://tests/wide_street_exit_check.gd # выезд из узкого двора на широкую улицу и следующий вопрос
godot --headless --path game_godot --script res://tests/impact_feel_check.gd # бордюр и удары по машинам зависят от угла, отброс машин
godot --path game_godot --resolution 448x970 --script res://tests/popin_ride_check.gd -- --benchmark --mute # что появляется/исчезает в кадре (только с рендером)
godot --headless --path game_godot --script res://tests/streaming_check.gd # выбор «В игре», подготовка и пауза
godot --headless --path game_godot --script res://tests/exit_loading_check.gd # выход во время фоновой сборки без потерянных узлов
godot --headless --path game_godot --script res://tests/staging_cancellation_check.gd # отмена воркера при закрытии/удалении владельца и выходе хоста
godot --headless --path game_godot --script res://tests/embedded_io_check.gd # iOS: повторные запуски основной игры и переходы после мини-игр
godot --headless --path game_godot --script res://tests/ambient_budget_check.gd # low: только декоративные люди, безопасная смена качества и неизменные участники задач
godot --headless --path game_godot --script res://tests/walking_budget_check.gd # точность тротуаров, ограниченный кеш и бюджет поиска пути пешеходов
godot --headless --path game_godot --script res://tests/walker_spacing_check.gd # свободное место при появлении, обход встречных и выход из наложения; native — снимки настоящего тротуара
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
tools/network/.venv/bin/python tools/network/tests/actor_turn_signals_check.py # реальный инспектор, ручные поворотники, неизменный путь и экспорт; фикстуры в scratch
godot --headless --path game_godot --script res://tests/actor_turn_signals_check.gd # ручной/автоматический сигнал, линзы всех типов транспорта, аварийка и ответ
tools/network/.venv/bin/python tools/network/tests/show_player_guide_check.py # экспорт переключателя синей стрелки на копиях, фикстуры в scratch
godot --headless --path game_godot --script res://tests/show_player_guide_check.gd # синяя стрелка/А-Б, старый guide.glb, камера и неизменный реальный проезд
godot --headless --path game_godot --script res://tests/question_camera_pose_check.gd # свободный ракурс вопроса, карточка, поворот локации и плавный прилёт/возврат
godot --headless --path game_godot --script res://tests/question_camera_occlusion_check.gd # параллельные лучи камеры и прозрачность зданий в удалённом низком ракурсе
godot --headless --path game_godot --script res://tests/tram_question_signals_check.gd # правые сигналы трамваев 15/13, 28/13, 36/14: линзы, ореолы, ответ, пауза и выключение
godot --headless --path game_godot --script res://tests/actor_hazards_check.gd # постоянная аварийка участников, стоянка, обе стороны, пауза и старые настройки
godot --headless --path game_godot --script res://tests/signal_glow_check.gd # свечение и цвета секций светофора без текстур
godot --headless --path game_godot --script res://tests/ride_pause_check.gd # быстрый старт, цвет, звук, сохранение состояния при паузе, карусель машин (снап, флик, тап по соседу, клавиши, круг); также -- --text-scale=1.6
godot --headless --path game_godot --script res://tests/reward_toast_check.gd # плашки открытий: очередь, анимации, HUD, ru/en/kk и темы; повторить с -- --text-scale=1.6
godot --headless --path game_godot --script res://tests/garage_rewards_check.gd # награды в заезде, продолжение, подтверждённые показы и пауза финальной плашки
godot --headless --path game_godot --script res://tests/ride_debug_menu_check.gd # скрытое меню dev-сборки: семь нажатий на «Пауза», размеры и локализации
godot --headless --path game_godot --script res://tests/debug_rewards_check.gd # тестовые плашки в игре без выдачи наград и изменения счётчиков
godot --headless --path game_godot --script res://tests/lifecycle_pause_check.gd # системное сворачивание/фокус, достижимая пауза и восстановление управления
godot --headless --path game_godot --script res://tests/question_report_check.gd # флажок/форма жалобы, ru/en/kk, маленькие экраны, пауза, повтор отправки и ответ хоста
godot --headless --path game_godot --script res://tests/exit_continuity_check.gd # все физические выезды, короткие улицы, полный кузов и стыковка следующего вопроса
godot --headless --path game_godot --script res://tests/lane_join_check.gd # подбор по фактическим полосам, въезд в 13/13 и плавные переходы 1+1 ↔ 2+2
godot --path game_godot --resolution 1280x900 --script res://tests/signal_glow_check.gd # нужен широкий кадр: видимое свечение, включая пакетный трафик
godot --path game_godot --script res://tests/building_fade_check.gd # нужен рендер: пачки прозрачных зданий и переиспользование
godot --headless --path game_godot --script res://tests/median_join_check.gd # разделительный газон на стыке сцен — сплошной, от носа до носа
tools/network/.venv/bin/python tools/network/tests/highway_check.py # фикстуры сквозных трасс и переходов, сохранение, сборка, весь кузов
godot --headless --path game_godot --script res://tests/highway_check.gd # реальные стыки 3+3 и 2+2 по фикстурам предыдущей команды
godot --headless --path game_godot --script res://tests/highway_run_check.gd # цепочка вопросов, переход 90 м, кривой въезд, разделители и кузов
godot --headless --path game_godot --script res://tests/ambient_lane_check.gd # фоновые машины и разделитель на стыке
godot --path game_godot --script res://tests/transport_audio_check.gd # шум шин, один голос на машину, реальная пауза кадра 110мс
godot --path game_godot --script res://tests/sound_resume_check.gd # звуки возвращаются после паузы и после фона (ОС остановила вывод)
godot --path game_godot --script res://tests/sound_check.gd # аудио: запуск, выключение, включение и освобождение
godot --path game_godot --script res://tests/occlusion_render_check.gd # нужен рендер: прозрачность зданий
godot --path game_godot --script res://tests/stitch_shader_render_check.gd # нужен рендер: мировая сетка текстур после стыковки
```

Скрипт с ошибкой в headless-режиме **зависает**, а не падает: ставьте таймаут
(`perl -e 'alarm 300; exec @ARGV' godot ...`). После изменения скриптов с `class_name`
выполните `godot --headless --path game_godot --import`.

Перед пакетным прогоном выполните три команды подготовки фикстур из списка:
`python3 tools/network/tests/actor_turn_signals_check.py`,
`python3 tools/network/tests/show_player_guide_check.py` и
`python3 tools/network/tests/highway_check.py`. Они пишут только одноразовые данные
в `scratch/`. Без них соответствующие Godot-проверки завершаются ошибкой или
зависают на `assert` — это отсутствие входных данных проверки.

В исправлениях от 18 октября 2026 закрыты ошибки старых фикстур: контактная тень
не считается лишней фарой, пешеходы переходов размещаются на настоящем тротуаре,
камера имеет согласованную историю позиции. Рендерные материалы отсоединяются
до удаления окрашенной машины/превью; закрытие владельца отменяет фоновую сборку
и освобождает захваченные ресурсы. `SCRIPT ERROR`, `ERROR` и утечки RID в журнале
нельзя считать успешной проверкой даже при коде завершения 0.

Проверки, завершающие движок после проигрывания MP3, ждут 0,12 с после удаления
сцены: аудиомикшер освобождает playback на реальном тике, а не за два быстрых
headless-кадра. Удаление World в тесте повторяет закрытие хоста: сначала `_exiting`,
затем два кадра для отмены фоновых continuations, затем `queue_free` и ожидание
удаления. Графические свойства MultiMesh проверяются native: dummy-рендерер
headless сбрасывает их буфер на границе кадра.

Дополнительные 27 проверок тем, озвучки, истории вопросов, быстрого разъезда,
разворотов и редакторских данных (вместе с основным списком — 118):

```bash
python3 tools/godot_export/export_question_audio.py
for game_check in actor_paint_check camera_check cd_shared_pictures_check \
  choice_line_check city_results_check connector_surface_check controls_theme_check \
  crossroads_adversarial_stress_check crossroads_fast_dispatch_check crossroads_interaction_check \
  dead_end_check kerb_angle_check loading_ready_check missing_player_route_check \
  question_history_check question_selection_check question_voice_check regulator_editor_check \
  regulator_walk_check sign_check stitch_check stitch_mesh_check stitch_runtime_check \
  turnaround_check ui_theme_check visual_geometry_check walker_wide_start_check; do
  godot --headless --path game_godot --script "res://tests/$game_check.gd"
done
```

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
Направление игрока берётся из `spec.maneuver`, участников — прежде всего из
`actors[].way` редактора, затем из `signalPlan` или `config.targetAction`.
Старые сцены читают `way` непосредственно из сети по ID участника; сохранённая
граница `signalPlan` по-прежнему выключает поворотник после манёвра. Геометрия
маршрута используется только при отсутствии заданного намерения. Разворот включает левый сигнал. Трамваи также показывают
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

Счётчик HUD показывает количество принятых ответов: сначала `0 / 20`, затем
прибавляет один за верный, неверный ответ или таймаут. Подъезд к новой локации
и её проезд счётчик не меняют. Верный 20-й ответ сразу завершает заезд без
дальнейшего манёвра; неверный ответ или таймаут сначала показывают разбор
с закреплённой внизу кнопкой «Завершить заезд». Обычные объяснения до 20-го
ответа сохраняют кнопку «Продолжить движение».

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
./scripts/godot_web_assets.sh         # игра для сайта: build/web/godot/
```

Релизный `scripts/build.sh` всегда пересобирает игры для своей платформы и
останавливается при отсутствии Godot/шаблонов, ошибке импорта, экспорта или
отсутствующем пакете. Android-архив дополнительно проверяется на `project.binary`
и ARM64-библиотеку движка; iOS-архив — на `Runner.pck`. Для Web нельзя выпустить
сборку без игры через старый `SKIP_GODOT_WEB`.

Импортеры Android/iOS/Web работают в частной копии проекта внутри `scratch/`;
исходные `.import` и настройки экспорта не переписываются. Ошибка сохраняет
предыдущие исправные файлы движка/пакета. Если общая MP3-озвучка ещё не подготовлена,
сначала выполните `python3 tools/godot_export/export_question_audio.py`.

Прямой dev-вызов Flutter без `android/godot/` по-прежнему позволяет проверять
учебную часть без игры (`GodotGame.available()` = false). Игра поддерживается
на Android ARM64; другие ABI получают сообщение о недоступности до запуска
Activity. Подробности — `game_godot/README.md` и комментарии в скриптах.

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

Звуки во всех трёх играх — общие с Flutter: `assets/audio/correct.wav`
и `incorrect.wav` (0,55 / 0,45), тиканье `tick.wav` (0,35) и праздничный
`streak.wav` при открытии машины или цвета (0,70). `GameSound` воспроизводит WAV без синтеза альтернативных
тонов. `PackFiles` читает общий ресурс: Android — через `PddHost.answerAudioBytes`,
iOS — через `--answer-audio-dir`, веб — из соседних Flutter-ресурсов,
компьютер — непосредственно из `assets/audio/`. Встроенная игра не хранит копий;
для standalone генератор `export_question_images.py --standalone` временно
подключает ссылки на исходные WAV. Праздничный звук играет и в плашке Godot,
и в резервном окне награды Flutter, если плашка не успела появиться до выхода.

Двигатели легковых машин, внедорожников, автобусов, грузовиков, мотоциклов,
электрический гул и двойной звонок трамвая, двухтональная сирена перенесены
из `assets/game/ambient-audio.js` в единый `GameSound`; WAV-дубли не создаются.
Двигатели звучат при движении, звонок — при его начале; явная сирена спецмашины
работает и на остановке. У обычной ДПС и жёлтых маячков сирены нет.
«Живой город» уменьшает громкость по расстоянию и озвучивает максимум четыре
ближайших/громких транспорта с приоритетом активной сирены; состояние не хранит
ссылок на удаляемые сцены. Пауза, выключение звука и выход останавливают также
общие записи. Шум шин проходит отдельный НЧ-фильтр; 240-мс кольцевой буфер
заполняется одним блоком на кадр. Затухание покинувшего сцену транспорта
начинается с запасом 80 мс, чтобы обычный интервал кадров не модулировал двигатель.
Проверки: `tests/sound_check.gd`, `tests/transport_audio_check.gd` и `tests/sound_resume_check.gd` (headless и native).
`tests/web_startup_audio_check.gd` проверяет HTTP-загрузку общих WAV при запуске
сцены: запросы начинаются после её присоединения к дереву, когда родитель уже
может принимать дочерние узлы `HTTPRequest`.

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

Флажок слева от номера билета открывает `question_report_dialog.gd`: форма
использует строки обычной жалобы из ARB и сохраняет текущий вопрос, таймер,
озвучку и участников через общую паузу заезда. Ошибка отправки оставляет текст
для повтора; закрытие формы возвращает к тому же вопросу с тем же временем.
`question_report_bridge.gd` передаёт в Flutter только сообщение, ID сцены и
текст вопроса: Android — через `ResultReceiver` между процессами, iOS — через
атомарные `report-request.json`/`report-result.json`, веб — через сообщения
между iframe и родителем с проверкой origin/source. Ответ сопоставляется с ID
попытки; ожидание ограничено 30 секундами. `QuestionReportService` добавляет
сведения об устройстве, ОС, версии, установке и действующую сессию; секреты
и сессия не попадают в аргументы Godot, URL или сохранение заезда. Серверный
журнал жалоб уже выводит эти сведения, а имя/email/ID берёт из подтверждённого
аккаунта. У гостя или аккаунта без email почту получить нельзя. Проверки:
`test/question_report_service_test.dart`, `server/install-notifier/test-question-reports.mjs`.
Во время отправки форма показывает вращающийся индикатор и `reportSending`
(ru/en/kk), сохраняя читаемый текст. При ошибке возвращаются действия для повтора.

Android: оба `ResultReceiver` перед помещением в Intent/Bundle преобразуются
в базовый класс через `GodotReportReceiver.remote()`. Анонимный подкласс нельзя
передавать напрямую: Bundle, созданный фреймворком `ResultReceiver`, распаковывает
его загрузчиком системных классов, из-за чего основной процесс падал с
`BadParcelableException` на имени `PddHostPlugin$...$reply$1`, а игра ждала 30 секунд.
Регрессионная проверка на подключённом Android воспроизводит исходное падение
и проверяет доставку успешного/неуспешного ответа после исправления:
`PDD_ANDROID_DEVICE_TESTS=1 python3 -m unittest discover -s tools/android_build -p test_report_receiver.py`.
Она устанавливает и удаляет отдельный временный тестовый APK, не запускает ПДД
и не отправляет сообщения на сервер. Логи `PddQuestionReport` содержат только этапы
передачи и результат, без текста жалобы и личных данных.
Экономика заездов и очков — `docs/game/game-economy-2026-10-10.md`.
Загрузчик и handover движка — [маскот WebP](../application/mascot-webp.md):
Host.loading сигнализирует готовый кадр, Android рисует нативный маскот,
iOS и веб используют загрузчик приложения до готовности игрового окна.

## Документы

- `crossroads-refinement-2026-10-15.md` — один формат «Разрули перекрёсток», интерфейс, общая атмосфера и аудит дорожной сцены
- `question-semantic-audit-2026-10-15.md` — смысловые повторы игровых заданий, исключённые сцены и сохранённые различия
- `garage-achievements.md` — общая палитра машин, награды за правильные ответы и перенос старого гаража
- `building-models.md` — модели домов, пересборка и ограничения для слабых телефонов
- `people-models.md` — модели пешеходов и регулировщика, походка и ограничения геометрии
- `walker-performance-2026-10-16.md` — стоимость обхода пешеходов, предел поиска за кадр и сравнение CPU на одинаковых состояниях
- `vehicle-models.md` — общий источник машин NPC/гаража и лёгкий отдельный транспорт
- `environment-models.md` — лёгкие деревья и уличные объекты с исходными точками установки
- `signs-and-signals.md` — знаки/светофоры, нормативные формы, серый оборот и сохранённые крепления
- `regulator-migration-2026-10-13.md` — паритет регулировщика и удаление WebView
- `regulator-performance-2026-10-15.md` — профили слабых телефонов, автоматический бюджет и контроль нагрузки регулировщика
- `ride-performance-2026-10-14.md` — очистка старых локаций по пути, длительный тест и диагностика dev-сборки
- `transition-performance-2026-10-15.md` — пакетная перестройка улиц, обрезка геометрии, неблокирующие замеры Android и остановленный фоновый транспорт
- `road-retirement-2026-10-15.md` — исчезновение дороги под машиной после лимита хранения и защита от застревания на траве
- `participant-lifetime-2026-10-15.md` — нативный вылет после удаления сбитого участника и регрессионная проверка
- `ride-completion-2026-10-15.md` — два штатных заезда, неверная нумерация HUD и оставшийся доступ к удалённому участнику
- `background-pause-2026-10-15.md` — исчезнувшее управление после сворачивания, безопасный показ паузы и продолжение
- `infinite-road-2026-10-15.md` — бесконечная прямая при поздней подготовке вопроса и наклонном выезде после ответа
- `infinite-road-2026-10-16.md` — пропущенный вопрос на узком подъезде при низком FPS и автоматическое обновление Godot в dev APK
- `infinite-road-2026-10-17.md` — бесконечная прямая за узким выездом (двор 5 м → улица 8.4 м), стык всегда впереди машины
- `popin-audit-2026-10-17.md` — замер появления объектов в кадре, листья без «выскакивания»
- `road-exit-continuity-2026-10-15.md` — тупик `ticket_20_6`, все физические выезды и стыки коротких дорог
- `ride-fixes-2026-10-13.md` — загрузка сцен, коллизии, продолжение маршрутов, интерфейс и гараж
- `local-changes-sync-2026-10-14.md` — опубликованные локации и архивы всех локальных stash
- `godot-roadmap.md` — что сделано и что открыто
- `godot-migration.md` — как и почему перешли на Godot
- `game-economy-2026-10-10.md`, `game-covers-2026-10-10.md`, `mini-game*.md` — экономика, обложки, мини-игры
- `games-hub-layout.md` — адаптивный каталог игр, состояния доступа, обложки и экспорт скриншотов

Стыковка билетов по фактическим концам дорог, ширине, полосам и разделителям —
[scene-stitching.md](scene-stitching.md) (устройство и три проверки стыковки).

Android-класс `GodotReportReceiver.java` должен лежать в `src/main/java/`, чтобы
Gradle включил его в DEX. Kotlin видит Java в `src/main/kotlin/` при компиляции,
но это не гарантирует упаковку. После сборки проверить реальный APK:
`PDD_VERIFY_DEV_APK=1 python3 -m unittest discover -s tools/android_build -p test_report_receiver.py`.

## Удары о бордюр и машины

Без физического движка, только кинематика в момент контакта (`drive.gd`, `world.gd`, `junction.gd`):
- **Бордюр под любым углом дороги.** Скольжение ищет наименьшее отклонение шага (до 60°),
  при котором кузов остаётся на дороге на метр вперёд, — так работают косые улицы после
  поворотов и изгибы сцен, а не только оси мира. Круче 60° — удар, не касание
  (`tests/kerb_angle_check.gd`).
- **Край грунтовки** скользит так же: стрелка, зажатая в косой или изогнутый край, не
  останавливает машину (скольжение пробует и прежний курс), а кадр без касания при
  скольжении не считается новым ударом (повторный удар — после 0,2 с без контакта).
  Край мягкой обочины (`field`) режется по линии «половина травы», без лесенки
  (`tests/kerb_angle_check.gd`, `tests/dirt_surface_check.gd`).
- **Бордюр.** В момент удара теряется только составляющая скорости, направленная в бордюр
  (доля фактического скольжения). Дальше при скольжении действует трение 2,5 м/с², и машина
  плавно доворачивается вдоль бордюра (1,6 рад/с). Удар почти в лоб (скольжение < 15%) — остановка.
- **Машины.** Прямота удара считается по нормали к стороне кузова, в которую пришёлся удар
  (борт, нос или корма). Прямой удар (> 0,75): игрок останавливается и отскакивает, как раньше.
  Скользящий: игрок теряет часть скорости и едет дальше. Ударенная машина отлетает
  (до 4 м/с, с трением 6 м/с²) и разворачивается от внецентренного удара. Машина сцены
  не въезжает при этом в игрока, других участников или за пределы своей дороги; трамвай
  не сдвигается. Потом машина плавно возвращается на свой маршрут или в полосу.
- Нарушение «столкновение» засчитывается как раньше.

## Тени и освещение (17.10.2026)

- **Косая «тень» за машиной** была краем ортогональной карты теней: на Mali-GPU
  (Pixel 9) после уменьшения карты до 1024 (`3e9022c1`) внутри неё земля слегка
  затеняла сама себя, и ровная косая граница ехала вместе с камерой; тень самой
  машины почти пропадала. Город перешёл на 2 каскада (`SHADOW_PARALLEL_2_SPLITS`,
  split 0,5, без смешивания): границы нет, тень машины чёткая. Проверено снимками с телефона.
- **Без теней картинка темнела на четверть.** Рендерер Compatibility освещает сцену
  примерно в 1,35 раза ярче, пока солнце отбрасывает тени. Уровень «low» и
  авто-понижение качества выключали тени — сцена тускнела. Теперь тени включаются и
  выключаются только через `Quality.set_sun_shadows()`, которая без теней поднимает
  солнце ×2,8 и рассеянный свет ×1,15 (в пределах ~10% от вида с тенями) во всех трёх играх.
- **Осень:** тёплый рассеянный свет `ambientTint` (`scenery/index.json`) в городе и
  мини-играх; небо мини-игр по-прежнему ясное во все сезоны.
- Для подбора на устройстве без пересборки: `--sun-bias=`, `--sun-normal-bias=`,
  `--sun-blur=`, `--sun-distance=`, `--sun-mode=split2|split4`, `--sun-fade=`,
  `--sun-energy-mul=`, `--ambient-mul=` (запуск через `adb ... --esa pdd_game_args`).
- Проверка: `godot --path game_godot --resolution 390x844 --script res://tests/shadow_light_check.gd -- --quality=high`.
