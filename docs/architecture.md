# Карта кода

Куда смотреть, чтобы найти нужное. Правила работы (git, строки, секреты,
сборка) — в `CLAUDE.md`; здесь только «где что лежит».

## Корень

| Путь | Что |
| --- | --- |
| `lib/` | Flutter-приложение (iOS, Android, веб) |
| `test/` | Flutter-тесты (`flutter test`) |
| `assets/countries/ru/` | Контент: билеты, знаки, ПДД, разметка, картинки |
| `assets/game/` | 3D-игра «Живой город» и мини-игры (Three.js в WebView) |
| `server/install-notifier/` | Cloudflare Worker: аккаунты, Премиум, оплаты, аналитика, админка |
| `web_landing/` | Лендинг и блог pdd-drive.ru (статика + генератор) |
| `scripts/` | Сборка, деплой, установка на телефон, генерация роликов |
| `tools/` | Вспомогательные инструменты (см. ниже) |
| `docs/` | Документация, индекс — `docs/README.md` |
| `android/`, `ios/`, `web/` | Платформенные проекты Flutter |
| `store_assets/`, `rustore_assets/` | Скриншоты и графика для сторов |
| `output/`, `scratch/`, `build/` | Временное (в `.gitignore`), не хранить там нужное |
| `secrets/` | Ключи (в `.gitignore`), в коде их быть не должно |

## lib/

```
lib/
  main.dart                    запуск, инициализация сервисов, уведомления
  core/
    config/                    CountryConfig (правила экзамена, контент), StoreConfig,
                               BackendConfig, экономика игры
    constants/                 AppColors, AppDimensions (дизайн-токены), маршруты, AppStrings
    theme/                     ThemeData
    navigation/, layout/, utils/
  data/
    models/                    Question, Streak, Achievement, UserProfile, модели мини-игр
    sources/                   локальные данные: прогресс (SharedPreferences), вопросы,
                               советы, сценарии мини-игры «Знаки»
    repositories/providers.dart  все Riverpod-провайдеры приложения
    services/                  сервисы: вход, Премиум, покупки, синхронизация, ИИ,
                               уведомления, аналитика, звук, озвучка
  domain/services/             чистая логика (движок мини-игры «Знаки»)
  l10n/                        строки ru/en/kk (*.arb) → gen/ генерируется
  presentation/
    screens/<экран>/           экраны: home (Обучение), tickets, topics, exam, training,
                               feed, profile, settings, signs, pdd, mistakes, favorites,
                               game (3D-игра), games (мини-игры)
    widgets/                   общие виджеты (пейвол, вход, серия дней, карточки)
```

Состояние — Riverpod (`data/repositories/providers.dart`). Прогресс хранится
локально (`ProgressDataSource`) и синхронизируется с сервером
(`ProgressSyncService`) для вошедших пользователей.

## Ключевые сценарии

| Сценарий | Начать с |
| --- | --- |
| Экзамен и его правила | `core/config/country_config.dart` (`ExamRules`), `screens/exam/`, `test/exam_flow_test.dart` |
| Вход, Премиум, оплата | `docs/premium/README.md` |
| Серия дней | `data/models/streak.dart`, `ProgressDataSource._markStreakActivityToday`, `widgets/streak_widgets.dart`, `widgets/streak_celebration_dialog.dart` |
| Достижения | `data/models/achievement.dart`, `screens/profile/` |
| 3D-игра | `docs/game/README.md` |
| Строки интерфейса | `lib/l10n/app_{ru,en,kk}.arb` → `flutter gen-l10n` |
| Уведомления | `data/services/notification_service.dart`, `docs/ops/notifications-setup.md` |

## tools/

| Папка | Что |
| --- | --- |
| `game_lab/` | Стенд сцен игры (`./scripts/game_lab.sh`) |
| `game_tests/` | Браузерные тесты и аудиты игры (Playwright) |
| `game_content/` | Сборка дорожных ситуаций игры |
| `game_reels/`, `signs_reel/`, `yt_upload/` | Ролики для соцсетей |
| `blog_admin/`, `seo/` | Генератор блога и SEO |
| `ru_content/`, `l10n/` | Сборка текста ПДД, переводы контента |
| `achievements/`, `store_graphics/` | Графика достижений и сторов |
| `git-hooks/` | Защита от коммита секретов |
