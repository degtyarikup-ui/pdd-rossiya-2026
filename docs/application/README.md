# Приложение Flutter

Часть единого репозитория: Android, iOS и веб используют `lib/` и российский контент.
Общие правила — [AGENTS.md](../../AGENTS.md), карта — [архитектура](../architecture.md).

## Где менять

| Задача | Начальная точка |
| --- | --- |
| Запуск и инициализация | `lib/main.dart` |
| Экран | `lib/presentation/screens/<экран>/` |
| Общий UI | `lib/presentation/widgets/` |
| Маскот и загрузчики | [WebP-анимация](mascot-webp.md), [3D-модель](mascot-3d.md), [векторные эксперименты](mascot-loader.md) |
| Состояние Riverpod | `lib/data/repositories/providers.dart` |
| Модели и локальные данные | `lib/data/models/`, `lib/data/sources/` |
| Запросы и интеграции | `lib/data/services/` |
| Правила страны | `lib/core/config/country_config.dart` |
| Дизайн | `lib/core/constants/`, `lib/core/theme/` |
| Строки | `lib/l10n/app_{ru,en,kk}.arb` |
| Нативные интеграции | `android/`, `ios/`, `web/` |

## Связи и ограничения

Вход, оплата и Premium требуют предварительного чтения [инвариантов](../premium/README.md).
Сервер — [карта backend](../server/README.md); формат синхронизации проверять
с обеих сторон (`progress_sync_service.dart`, `progress_merge.js`).
Контент и его генераторы — [карта контента](../content/README.md).
Godot — [инструкции игры](../game/README.md); платформенные пакеты генерируются отдельно.

Любое изменение UI-строк делается сразу в ru/en/kk, затем `flutter gen-l10n`.
`lib/l10n/gen/` не редактировать вручную. Регламент не дублировать в экранах.

## Проверки и сборка

Из корня: `flutter analyze`, `flutter test`; дополнительные проверки —
[testing.md](../testing.md). Сборки — `scripts/build.sh`; dev-установка —
`scripts/install_dev.sh`. Секрет сборки берётся из локального `secrets/`.
`build/` и кэш `.dart_tool/flutter_build/` восстанавливаются при сборке.
