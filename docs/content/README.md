# Контент и сайт: источники и результаты

## Что редактировать

| Область | Источник | Результат / генератор |
| --- | --- | --- |
| Билеты, темы, знаки, разметка | `assets/countries/ru/questions/*.json` | Используются приложением |
| Иллюстрации вопросов и знаков | `assets/countries/ru/images/` | Используются приложением |
| Текст ПДД | `tools/ru_content/raw/` | `tools/ru_content/parse_pdd.py` → `pdd_sections.json` |
| Народные названия знаков | `tools/ru_content/add_folk_names.py` | `folkName` в `signs.json` |
| UI ru/en/kk | `lib/l10n/app_*.arb` | `flutter gen-l10n` → `lib/l10n/gen/`; `tools/godot_export/export_ui.py` → строки игры |
| Статьи | `web_landing/ru/blog/<slug>/source.json` | `tools/blog_admin/generator.py` → HTML и индексы |
| Словарь | `web_landing/ru/glossary_data/batch-*.json` | `render_glossary()` в генераторе блога |
| Преамбула для LLM | `tools/blog_admin/llms_preamble.md` | Генератор → `llms*.txt` |
| Дизайн сайта | `web_landing/ru/assets/style.css`, `web_landing/_shared/template.html` | Статические страницы и шаблон генератора |
| Сеть Godot | `game_godot/network/*.json` | Редактор → `network/build/` и `situations/*/scene.json` |

Текст ПДД официальный и дословный. Парсер проверяет нумерацию; новые формулировки
не придумывать. Правила изображений блога — в корневых инструкциях.
После пересборки знаков повторно добавлять народные названия.

## Что не редактировать вручную

`blog/*/index.html`, `blog/index.html`, sitemap и llms-файлы — результаты
генератора блога. `robots.txt` также считать артефактом согласно корневым
инструкциям; не менять вручную. Пересборка блога из корня:
`python3 tools/blog_admin/generator.py regen`.
Не запускать генераторы ради проверки документации: они меняют артефакты.
`game_godot/network/build/` тоже генерируется, но хранится в Git и коммитится
вместе с исходной сетью и сценами. Не путать его с корневым `build/`.

## Публикация и ролики

Лендинг и блог: `./scripts/deploy_landing.sh ru`.
Веб-приложение: `./scripts/deploy_web.sh ru`, адрес `pdd-drive.ru/app/`.
Обычный деплой лендинга сохраняет `/app/`.
Локальная админка — [инструкция](../admin/README.md).

Для блога `published: true` разрешает выпуск, а `datePublished` задаёт день
публикации по МСК. Генератор включает в HTML, индексы, RSS, sitemap и llms
только статьи, дата которых наступила. Будущие статьи и черновики видны
в локальном редакторе; при пересборке их старые `index.html` удаляются.
Деплой всегда пересобирает блог и исключает из публичной копии их каталоги
и все `source.json`. Исходники остаются в репозитории.

Новые статьи могут содержать `reviewedAt` (дата проверки, отдельно от выхода),
`sources: [{title, url}]` (источники и JSON-LD citation), `relatedSlugs`
(предпочтительные ссылки только на уже вышедшие статьи),
`cta: {title, text, label, href}`. Ссылка CTA — `/app/`,
`/proverit-znaniya/` или `/#download`: переходы к конкретным темам приложение пока не поддерживает.
`article_practice_click` в Метрике измеряет нажатие CTA статьи, а не начало
экзамена. Трекер отдельно распознаёт Google, Яндекс, Bing и известные ИИ-рефереры;
отсутствующий Referer нельзя достоверно приписать ИИ.

Проверки границы редактор/публикация и трекера:

```bash
python3 -m unittest tools.blog_admin.test_generator
node --test tools/blog_admin/test_tracker.cjs
python3 tools/seo/audit.py --quiet
```

Видео: [знаки](../../tools/signs_reel/README.md),
[вопросы из билетов](../../tools/signs_reel/QUESTION_REELS.md),
[перекрёстки в белом 3D-макете](../video/reels_3d.md)
и [десять следующих сценариев](../video/intersection_reels_scenarios.md).
`tools/signs_reel/state.json` — сохраняемый реестр выпусков, не кэш.
Готовые видео и кэш пайплайна могут занимать много места; опубликованные выпуски
не следует удалять без проверки, что сохранена нужная копия.

## Идентичность вопросов и восстановление иллюстраций

Исходный `id` обозначает текст и студийное аудио; он не всегда уникален для
иллюстрации. Вторая карточка с тем же `id` получает `variantId` с координатами
билета. Приложение хранит прогресс по `variantId`, а для аудио использует исходный
`id`. Старый прогресс копируется на обе карточки один раз; последующие ответы и
избранное независимы, удалённое избранное при облачной синхронизации не возвращается.

После изменения билетного источника выполнить:

```bash
python3 tools/ru_content/repair_question_identity.py
python3 tools/ru_content/test_release_content.py
flutter test test/question_identity_test.dart
python3 tools/godot_export/export_question_images.py
```

Скрипт связывает темы с билетами по полному объяснению, сохраняет координаты и
тексты на всех трёх языках. Манифест восстановленных диаграмм и SHA-256 —
`tools/ru_content/question_image_repairs.json`; исходный upstream тоже склеивает
картинки повторных ID, поэтому не заменять их по одному только ID. Смена текста
в восстановленной позиции требует повторной проверки диаграммы.

Поправка к сноске пункта 2.1.1 (постановление от 28.08.2026 №1088) внесена в
`tools/ru_content/raw/pdd2.html`; точный текст, официальный URL и хеш PDF —
`tools/ru_content/amendment_2026_1088.json`. Пересборка ПДД сохраняет эту поправку.

## Данные вопросов в Telegram-жалобах

`tools/ru_content/export_report_questions.py` собирает из русских билетных JSON
каталог верных ответов и изображений для Worker:
`server/install-notifier/report_questions_data.js`. После изменения вариантов,
правильных ответов, ID или картинок пересобрать каталог; `--check` проверяет
актуальность без записи. Проверка включена в `npm run test:reports`.

Пояснение к A/B 26–20 сверено с официальным файлом комментариев ГИБДД
`https://госавтоинспекция.рф/upload/site1000/folder/original/avtovladeltsam/fees/abm/26-komment-abm-2018.pdf`
(пункт 20, редакция файла 2018 года). В ru — оригинал, в en/kk — его переводы;
билетная и тематическая версии синхронны. Ответ: вариант 2, «2 секунды».
