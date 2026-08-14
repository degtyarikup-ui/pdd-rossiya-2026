# ПДД 2026 — мультистрановое приложение (Flutter)

Один код — несколько стран. Сейчас: Россия (`ru`), Беларусь (`by`),
Сербия (`rs`, латиница).

## Главное правило

**Любая правка визуала/логики автоматически относится ко всем странам.**
Страно-зависимое запрещено хардкодить в экранах — только через
`lib/core/config/country_config.dart` (`CountryConfig.current`):
правила экзамена (`ExamRules`), названия, пути контента, наличие C/D,
язык интерфейса (`language`).

Страна выбирается при сборке: `--dart-define=COUNTRY=ru|by|rs`
(+ Android flavor с тем же именем). По умолчанию `ru`.

## Две независимые оси: страна и язык

- **Страна** (build-time): контент, правила экзамена, идентичность, `language`.
- **Язык UI** (`CountryConfig.language`, фиксирован под страну): RU/BY → `ru`,
  RS → `sr`. Рантайм-переключателя нет — каждое приложение одноязычное.

## Интернационализация (i18n)

Все строки UI — в ARB через gen-l10n (`flutter gen-l10n`), НЕ хардкодить
кириллицу/латиницу в экранах.

- `lib/l10n/app_ru.arb` — шаблон (русский, RU/BY). `lib/l10n/app_sr.arb` —
  сербский (латиница). Множественные формы/подстановки — ICU-плюралы
  (у сербского формы one/few/other отличаются от русского one/few/many).
- Доступ вне контекста (язык фиксирован сборкой): глобаль `appL10n` из
  `lib/l10n/l10n.dart` — `appL10n.exam`, `appL10n.questionOfTotal(i, n)`.
  Настройки gen-l10n — в `lib/l10n.yaml`; сгенерённое в `lib/l10n/gen/`.
- `lib/core/constants/app_strings.dart` — тонкая обёртка над `appL10n`
  (историческая совместимость `AppStrings.*`).
- Новый язык = один ARB `app_<lang>.arb` + `language` в конфиге страны.

## Контент стран

```
assets/countries/{code}/questions/  questions_ab.json, topics_ab.json,
                                    signs.json, pdd_sections.json
assets/countries/{code}/images/     questions_ab/, signs/, ...
```

- RU: 40 билетов × 20 (A/B и C/D). Текст ПДД — **официальный, дословный**
  (пост. Правительства РФ №1090): 26 разделов, 200 пунктов, ~215 КБ,
  собирается `tools/ru_content/parse_pdd.py` из сохранённых страниц в
  `tools/ru_content/raw/`. Парсер падает, если нумерация пунктов разъезжается
  с номером раздела. Надстрочные пункты закона (9.1¹, 13.11¹) разворачиваются
  в 9.1.1 / 13.11.1 — так их цитируют разборы вопросов.
  Народные названия знаков — `tools/ru_content/add_folk_names.py`
  (поле `folkName` в signs.json, перезапускать после пересбора знаков).
- BY: стартовая база 7 билетов × 10 (77 вопросов), знаки СТБ (195),
  полный официальный текст ПДД РБ (27 глав, ред. 01.09.2025). Только A/B.
- RS: латиница, баллы (`points` 1/2/3). Только A/B. Контент из двух источников:
  - **Официальная база MUP** (публичная, разрешено некоммерч. распространение):
    вопросы+картинки из PDF `prezentacije.mup.gov.rs/usp/Vozacki ispit/…`
    (Pravila saobraćaja 778, Saobraćajna signalizacija 524 и т.д.). В PDF нет
    ключа ответов (кроме 5 спец.), поэтому правильный ответ определяется
    отдельно (зрение) и проверяется. Картинки вопросов — JPG в `images/questions_ab`.
  - **Знаки** — реальные SVG Венской конвенции с Wikimedia Commons (свободная
    лицензия), файлы `Serbia_road_sign_<код>.svg` → `images/signs/<код>.svg`;
    сербские названия/описания сгенерированы. 101 знак, 3 категории MUP.
  - **Текст правил** (`pdd_sections.json`, вкладка «Propisi») — ⚠️ ПОКА
    АВТОРСКИЙ пересказ: 11 коротких секций (~3 КБ), НЕ дословный закон.
    Нужно заменить на официальный Zakon o bezbednosti saobraćaja na putevima
    (Sl. glasnik RS 41/2009…19/2025) — по образцу BY, где лежит полный
    официальный текст (~308 КБ, 27 глав). Пайплайна парсинга закона (аналога
    `by_content`) для RS ещё нет.
  - Вопросы — **только официальная база MUP** (1763 из 1764 подтверждены;
    единственный `posledice_0159` — см. `tools/rs_content/PENDING_REVIEW.md`);
    авторская база вопросов удалена полностью.
  - Разметка (`markup.json`) — тоже пока авторское краткое изложение (8 пунктов),
    не дословный источник (см. `build_reference.py`).
- Пайплайны: `tools/by_content/`; `tools/rs_content/`:
  `build_questions.py` (официальные → questions/topics, `TICKET_SIZE`=41),
  `build_reference.py` (только разметка — авторская),
  `download_signs.py`+`build_signs_final.py` (знаки Wikimedia → signs.json),
  `extract_questions.py` (MUP PDF → структурированный JSON + картинки, кириллица→латиница),
  `build_official_questions.py` (master+подтверждённые ответы → схема приложения),
  `rs_official_answers_workflow.js` (не в репо — воркфлоу определения+
  верификации ответов: 2 независимых прохода + судья при расхождении).
  Данные пайплайна в репо: `master_dataset.json` (все 1764),
  `confirmed_answers.json` (подтверждённые), `pending_review_questions.json`.
  Парсера официального закона для RS пока НЕТ (см. «Текст правил» выше).

## Правила экзамена (зашиты в CountryConfig)

`ExamRules.scoring` выбирает модель подсчёта:

- **`mistakes`** (RU/BY) — «≤N ошибок», возможна доп. фаза.
  - RU: 20 вопросов / 20 мин / ≤2 ошибки / +5 вопросов и +5 мин за ошибку,
    ошибка в доп. блоке = провал (регламент ГИБДД).
  - BY: 10 вопросов / 15 мин / ≤1 ошибка / доп. вопросов нет (регламент ГАИ РБ).
- **`points`** (RS) — весовые баллы: вопрос `points` 1/2/3, сдал при наборе
  ≥ `passPercent`% от максимума. Доп. фазы и досрочного провала нет.
  - RS: 41 вопрос / 45 мин / порог 85% (регламент MUP).
  - Поле `points` у вопроса (`Question.points`, по умолчанию 1); ветвление
    в `exam_screen.dart` по `rules.scoring`. Тесты обеих моделей —
    `test/exam_flow_test.dart`.

## Сборка и деплой

```bash
./scripts/build.sh ru|by|rs aab|web   # сборка страны
./scripts/deploy_web.sh ru|by|rs      # веб-деплой приложения страны
./scripts/deploy_landing.sh ru        # деплой лендинга/блога (только ru)
flutter gen-l10n                       # регенерация локализаций из ARB
flutter test                           # тесты всех моделей (exam_flow_test)
```

- Тестовая сборка на своё устройство — флаг `-Pdev` (суффикс `.dev`
  к applicationId), ставится РЯДОМ с магазинной:
  `flutter build apk --flavor ru --release --dart-define=COUNTRY=ru -Pdev`.
  Без суффикса установка поверх магазинной невозможна: в Play включена
  подпись Google (Play App Signing), локальная сборка подписана upload-ключом,
  и Android считает их разными приложениями (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`).
  На обычные сборки флаг не влияет.
- Android: flavors `ru` (ru.pdd.pdd_app) / `by` (by.pdd.pdd_app) /
  `rs` (rs.pdd.pdd_app), подпись одним ключом `android/upload-keystore.jks`
  (в .gitignore). AAB: `build/app/outputs/bundle/{flavor}Release/...`.
- Иконки flavor'ов: `flutter_launcher_icons-{ru,by,rs}.yaml`
  → `dart run flutter_launcher_icons`.
- Веб RU — два сайта:
  - **Лендинг + блог** (SEO): исходники `web_landing/ru/` (чистая статика,
    дизайн-токены = AppColors/AppDimensions в `assets/style.css`, общий
    шаблон страниц `web_landing/_shared/template.html`) →
    `deploy_landing.sh ru` → репо `pdd-rossiya-2026` gh-pages → pdd-drive.ru.
    SEO/GEO-файлы: sitemap.xml, robots.txt (22 блока AI-краулеров), llms.txt,
    llms-full.txt — **генерируются**, руками не править.
    - **Блог = генератор**: источник статьи — `blog/<slug>/source.json`,
      страницы собирает `tools/blog_admin/generator.py` (`regen`).
      `blog/*/index.html`, `blog/index.html`, sitemap, llms* — АРТЕФАКТЫ,
      правки в них затрутся; менять надо source.json / generator.py /
      `tools/blog_admin/llms_preamble.md`.
    - **Админка**: `./scripts/blog_admin.sh` → http://127.0.0.1:8930/admin
      (только localhost). Редактор статей, загрузка обложек и картинок в текст,
      черновики (`published: false` — видны в предпросмотре, но не в
      индексе/sitemap/llms), кнопка «Опубликовать на сайт» =
      deploy_landing.sh + IndexNow-пинг.
    - **Скриншоты приложения** (мокапы для сайта): `tools/blog_admin/gen_images.py`
      генерирует AI-иллюстрации (Nano Banana), а реальные скрины UI снимаются
      Playwright headless по build/web (CanvasKit → клики только по координатам,
      см. память проекта); готовые PNG → `web_landing/ru/assets/screenshots/`.
      Использованы в hero главной, галерее «Как выглядит приложение» и внутри
      статей.
    - **Словарь терминов** `/slovar-pdd/`: источники `web_landing/ru/glossary_data/
      batch-*.json` (6 тематических JSON, схема `{batch, terms:[{term,slug,
      definition,seeAlso}]}`), рендерит `render_glossary()` в generator.py —
      DefinedTermSet-разметка, авто-подключён в sitemap/llms.txt/llms-full.txt.
  - **Приложение**: `deploy_web.sh ru` → репо `pdd-rossiya-app` gh-pages →
    app.pdd-drive.ru (robots.txt Disallow: SEO живёт на лендинге; DNS: CNAME
    `app` → degtyarikup-ui.github.io на reg.ru).
- Веб BY: репо `pdd-belarus` gh-pages → pdd-drive.online
  (локальный клон: `/Users/sergei/Documents/pdd-belarus`).
- Веб RS: репо `pdd-serbia` gh-pages → rs.pdd-drive.online (поддомен).

## Ролики «Успей узнать знак» (Shorts/Reels/TikTok)

```bash
./scripts/make_reel.sh                        # категории и остаток знаков
./scripts/make_reel.sh "Запрещающие знаки"    # выпуск 1080×1920 в assets/videos/signs_reel/
```

Пайплайн `tools/signs_reel/` (подробности — его README): знак → 3 секунды
отсчёта → ответ → финальная сетка всех знаков выпуска. Кадр повторяет экран
приложения, `config.py` — зеркало `AppColors`/`AppDimensions`, переход =
`QuestionSwipeMotion`; над карточкой ничего нет, время показывает полоса
цветом, теней не используем. Фон — одна из 10 сгенерированных сцен со знаками
(`backgrounds.py`) под брендовым синим. Текст интро — субтитрами по 1–2 слова,
в финале вместо них анимированная плашка `banner.webm` (VP9 с альфой,
декодировать только через `libvpx-vp9`). Звук: голос (Gemini TTS, `Algenib`)
+ тиканье, музыки нет.

- Контент только из `signs.json` — знаки не рисуются нейросетью,
  формулировки не пишутся по памяти.
- Отбор отсекает дубли названий и картинок: одинаковый ответ у двух знаков
  делает вопрос нерешаемым.
- Вышедшие знаки пишутся в `tools/signs_reel/state.json` (коммитится) —
  следующий выпуск той же категории берёт другие.
- Перед выдачей: озвучка расшифровывается обратно и сверяется с текстом,
  длины видео и звука сверяются с точностью до кадра.
- Проект Google Cloud — из ADC (`quota_project_id`), не из константы.

## Добавление новой страны NN

1. `CountryConfig.nn` (`language`, `scoring`, правила экзамена, названия) +
   ветка в `current`.
2. Язык: если новый — `lib/l10n/app_<lang>.arb` + `flutter gen-l10n`.
3. Контент в `assets/countries/nn/` (+ пайплайн `tools/nn_content/`) +
   регистрация в pubspec assets.
4. Flavor в `android/app/build.gradle.kts` + `flutter_launcher_icons-nn.yaml`.
5. Кейс в `scripts/build.sh` и `scripts/deploy_web.sh` (репо/домен/титулы).
6. Тесты правил экзамена в `test/exam_flow_test.dart` (BY — образец для
   `mistakes`, RS — для `points`).

## Окружение сборки

- `flutter` в `$HOME/flutter/bin`; Java: `/opt/homebrew/opt/openjdk@17`.
- Прод-версии в `pubspec.yaml` (`version:`); versionCode общий для стран.
