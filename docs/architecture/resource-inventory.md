# Инвентаризация ресурсов RU — 2026-11-09

Все перечисленные учебные и игровые ресурсы принадлежат RU.
Пути в этой инвентаризации указаны относительно `apps/russia/`. В общий UI-пакет они не входят.

| Объявленный путь Flutter | Файлов | Размер файлов, МиБ |
| --- | ---: | ---: |
| `assets/images/` | 17 | 1.07 |
| `assets/images/category_icons/` | 10 | 0.01 |
| `assets/images/tips/` | 20 | 2.80 |
| `assets/images/achievements/` | 44 | 1.55 |
| `assets/images/games/` | 18 | 1.00 |
| `assets/images/premium/` | 18 | 2.41 |
| `assets/icons/auth/` | 4 | 0.00 |
| `assets/icons/game/` | 5 | 0.01 |
| `assets/audio/` | 6 | 0.44 |
| `assets/audio/feed/` | 1092 | 30.87 |
| `assets/audio/game_questions/` | 236 | 30.93 |
| `assets/game/` | 19 | 1.20 |
| `assets/game/garage/` | 64 | 0.92 |
| `assets/game/garage_turntable/` | 64 | 16.34 |
| `assets/mascot/raster/cone-juggling-384-30.webp` | 1 | 0.86 |
| `assets/mascot/raster/cone-juggling-poster-384.webp` | 1 | 0.02 |
| `assets/countries/ru/questions/` | 25 | 15.86 |
| `assets/countries/ru/images/questions_ab/` | 560 | 41.20 |
| `assets/countries/ru/images/questions_cd/` | 549 | 11.31 |
| `assets/countries/ru/images/signs/` | 320 | 0.92 |
| `assets/countries/ru/images/markup/` | 62 | 0.07 |

Для каталогов здесь учитываются непосредственные файлы, как в декларациях Flutter;
вложенные каталоги подключаются отдельно. Шрифты — отдельный список в resource_policy.json.

| Артефакт | Несжатые данные / размер PCK, МиБ |
| --- | ---: |
| `ru-android-universal` | 343.89 |
| `ru-android-aab` | 483.13 |
| `ru-flutter-assets` | 145.36 |
| `ru-ios-game` | 89.35 |
| `ru-web` | 380.63 |

Это существующие локальные артефакты одной машины, не новая магазинная версия.
Несжатая сумма не равна размеру скачивания. Порог +15% применяется только к явно
выбранному сопоставимому профилю; APK dev ARM64 не сравнивается с универсальным APK.

Android Godot: `android/godot/assets/` добавляется native sourceSet;
движок `godot-lib.aar` подключается отдельно. iOS: `ios/Godot/game.pck` копируется
в Runner.pck; Web: отдельный `godot/index.pck` плюс потоковые сцены.
PCK iOS содержит 10291 запись, PCK Web — 1775 записей (базовые артефакты).
Аудитор проверяет внутренние пути и страну сцен, не меняя содержимое архивов.

Применимость изображения/озвучки без метки страны определяется при подготовке
контента, а не автоматически по двоичному файлу. Копировать эти папки в BY запрещено
без отдельного отбора и проверки. Старые BY/RS не используются.
