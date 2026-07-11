# ПДД 2026 — мультистрановое приложение (Flutter)

Один код — несколько стран. Сейчас: Россия (`ru`) и Беларусь (`by`).

## Главное правило

**Любая правка визуала/логики автоматически относится ко всем странам.**
Страно-зависимое запрещено хардкодить в экранах — только через
`lib/core/config/country_config.dart` (`CountryConfig.current`):
правила экзамена (`ExamRules`), названия, пути контента, наличие C/D.

Страна выбирается при сборке: `--dart-define=COUNTRY=ru|by`
(+ Android flavor с тем же именем). По умолчанию `ru`.

## Контент стран

```
assets/countries/{code}/questions/  questions_ab.json, topics_ab.json,
                                    signs.json, pdd_sections.json
assets/countries/{code}/images/     questions_ab/, signs/, ...
```

- RU: 40 билетов × 20 (A/B и C/D), полный ПДД РФ.
- BY: стартовая база 7 билетов × 10 (77 вопросов), знаки СТБ (195),
  полный официальный текст ПДД РБ (27 глав, ред. 01.09.2025). Только A/B.
- Пайплайн контента BY: `tools/by_content/` (парсеры + генератор вопросов).
  Расширение базы: добавить вопросы в `build_questions.py` и перегенерить.

## Правила экзамена (зашиты в CountryConfig)

- RU: 20 вопросов / 20 мин / ≤2 ошибки / +5 вопросов и +5 мин за ошибку,
  ошибка в доп. блоке = провал (регламент ГИБДД).
- BY: 10 вопросов / 15 мин / ≤1 ошибка / доп. вопросов нет (регламент ГАИ РБ).

## Сборка и деплой

```bash
./scripts/build.sh ru|by aab|web     # сборка страны
./scripts/deploy_web.sh ru|by       # веб-деплой страны
flutter test                         # тесты обеих стран (exam_flow_test)
```

- Android: flavors `ru` (ru.pdd.pdd_app) / `by` (by.pdd.pdd_app),
  подпись одним ключом `android/upload-keystore.jks` (в .gitignore).
  AAB: `build/app/outputs/bundle/{flavor}Release/app-{flavor}-release.aab`.
- Иконки flavor'ов: `flutter_launcher_icons-{ru,by}.yaml`
  → `dart run flutter_launcher_icons`.
- Веб RU: репо `pdd-rossiya-2026` gh-pages → pdd-drive.ru.
- Веб BY: репо `pdd-belarus` gh-pages → pdd-drive.online
  (локальный клон: `/Users/sergei/Documents/pdd-belarus`).

## Добавление новой страны NN

1. `CountryConfig.nn` (правила экзамена, названия) + ветка в `current`.
2. Контент в `assets/countries/nn/` + pubspec assets.
3. Flavor в `android/app/build.gradle.kts` + `flutter_launcher_icons-nn.yaml`.
4. Кейс в `scripts/build.sh` и `scripts/deploy_web.sh` (репо/домен/титулы).
5. BY-тесты в `test/exam_flow_test.dart` как образец параметризации.

## Окружение сборки

- `flutter` в `$HOME/flutter/bin`; Java: `/opt/homebrew/opt/openjdk@17`.
- Прод-версии в `pubspec.yaml` (`version:`); versionCode общий для стран.
