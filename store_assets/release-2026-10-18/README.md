# Карточки к релизу — 18 октября 2026

Открыть `index.html` или взять все 18 экспортов из `publishing-kit.zip`.
Шесть сюжетов, из них четыре игровых: «Живой город», «Перекрёсток»,
«Регулировщик», «Это знак», затем билеты и прогресс.

- Google Play: `google-play/`, PNG 1080×1920 без alpha.
- RuStore: `rustore/`, JPG 1080×1920, каждый меньше 3 MiB.
- App Store: `app-store/`, PNG 1260×2736 без alpha, слот iPhone 6.9″.

Исходники в `raw/`: Godot desktop Compatibility — фактические PNG 586×1266;
Flutter — локальная web release в Chrome, 390×844 CSS px при DPR 3. Нельзя
считать эти кадры проверкой финальной подписанной сборки на телефоне.
Перед отправкой в магазины сверить внешний вид и механики с Android/iPhone.
Текущий iOS target — только iPhone (`TARGETED_DEVICE_FAMILY = 1`).

Встроенный ImageGen создал три концепта в `generated/`; точные промпты —
`generated/prompts.json`. Это направление дизайна. Финальные publishing
экспорты используют оригинальные кадры с сохранением пропорций, без
генеративной перерисовки интерфейса. `manifest.json` фиксирует размеры,
байты, происхождение и размещение кадра.

Повторная сборка на этой машине:

```bash
NODE_PATH=/Users/sergei/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules \
  node tools/store_graphics/release_2026_10_18.cjs
```

Нужны `sharp`, `@napi-rs/canvas`, `/usr/bin/zip`, шрифт Onest из репозитория
и кадры в `output/release-audit-2026-10-18/screenshots/`. Генератор сохраняет
исходные изображения и проверяет размеры, alpha и лимит RuStore. Набор
сохранён отдельно от старых карточек. В кабинеты магазинов ничего не загружалось.
