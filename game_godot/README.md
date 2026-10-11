# Игра на Godot — пробная сцена (spike)

Ветка `game-rewrite`. Проверка, что Godot 4.7 даёт быстрый кадр на телефонах,
до переноса игры целиком. Откат к прежней игре — тег `game-before-rewrite`.

## Запуск

```bash
godot --path game_godot                                   # окно на Mac
godot --path game_godot -- --shot=output/godot-spike.png  # 4 с с газом → кадр
godot --headless --path game_godot --export-release "Android" ../output/godot/pdd-game-spike.apk
godot --headless --path game_godot --export-release "iOS" ../output/godot/ios/PDDGameSpike.xcodeproj
```

iOS собирается из сгенерированного Xcode-проекта: `xcodebuild ... DEVELOPMENT_TEAM=6T66V45XC7
CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development"`, ставится `xcrun devicectl
device install app`. Пакет `ru.pdd.godotspike` — отдельное приложение, магазинное не трогает.

## Веб (сайт, /app/godot/)

`./scripts/godot_dev.sh web` — экспорт Web (nothreads, без SharedArrayBuffer) в
`build/web/godot/`. `./scripts/build.sh ru web` делает это сам, если есть `godot` и
`game_godot/situations`; иначе на сайте остаётся старая игра (`SKIP_GODOT_WEB=1` — без Godot).

- В `index.pck` (~11 МБ) — движок-данные, модели, сети, список вопросов. Первая загрузка
  ~16 МБ по gzip (движок ~10 МБ). Сцены перекрёстков (`situations/<id>/`, ~0.7 МБ каждая) и
  картинки билетов (`questions/*.webp`) лежат рядом и грузятся по требованию
  (`scripts/pack_files.gd`): перекрёсток — когда его надо поставить, картинка — при нажатии.
- Вызов из приложения: `GodotGame` (`lib/presentation/screens/game/godot_game.dart`) открывает
  `godot/index.html?lang=ru&dark=1` в iframe на весь экран (`GodotWebScreen`).
  `available()` на вебе — есть ли `godot/index.pck` на сайте.
- Мост: игра шлёт родителю `postMessage({bridge: 'pdd-godot', kind: 'exit', json: <итог заезда>})`
  (`scripts/host.gd`, `Host.exit`); аргументы приходят из query-строки (`--k=v` ↔ `k=v`, `--k` ↔ `k=1`).
- Управление: сенсорные педали и руль (`controls.gd`); с клавиатуры: W/стрелка вверх — газ,
  S/стрелка вниз/пробел — тормоз, A/D или стрелки — руль (физические клавиши).
- Тест локально: `python3 -m http.server 8960 --bind 127.0.0.1 --directory build/web`, открыть
  `http://127.0.0.1:8960/godot/index.html?lang=ru&situation=ticket_10_13&topdown=x.png&mute=1`
  (`topdown` ставит перекрёсток сразу; `auto=1` — автопилот, в медленном браузере долго).

## Как устроено (и почему не так, как в WebView-игре)

| | WebView (Three.js) | Godot |
|---|---|---|
| Рендер | WebGL в WebView | Compatibility (GLES3 / ANGLE-Metal) напрямую |
| Повторяющиеся объекты | отдельный меш и материал на каждый (≈3900 мешей, 2500 материалов) | один `MultiMesh` на вид: дома, крыши, деревья, фонари, машины, пешеходы |
| Улица | новые сегменты создаются и удаляются | кольцо чанков, переиспользуется: объектов не прибавляется |
| Управление | Flutter → `runJavaScript` → JS (сейчас — страница) | обработчик касаний в том же кадре |
| Внешний вид | в коде | `data/world.json` |

Файлы: `scripts/world.gd` (улица, движение, чанки), `scripts/controls.gd` (педали,
мультитач), `scripts/perf_hud.gd` (счётчик — те же цифры, что у `perf-hud.js`;
тап по нему переключает уровень low → mid → high), `scripts/quality.gd`
(уровень по видеочипу, таблица = `assets/game/quality-tier.js`).

## Первые замеры

| | WebView | Godot |
|---|---|---|
| Pixel 9 Pro XL, вызовов отрисовки | 210 | 41 |
| Pixel 9 Pro XL, кадр | 8.3 мс (120 Гц) | 16.7 мс (60 — лимит vsync сборки) |
| Объектов в сцене через 500 м | растёт (799 → 1494 геометрий) | постоянно (42 узла) |


## Флаги для проверки на компьютере

Все флаги идут после `--` (например `godot --path game_godot -- --situation=ticket_5_14 --near --auto`):

- `--situation=<id>` — ехать только через один перекрёсток (id из `situations/index.json`).
- `--near` — сразу поставить машину в 12 м до стоп-линии первого перекрёстка.
- `--auto` — автопилот: газ, торможение за машиной, автоматический правильный ответ (для проверки езды, не для игры).
- `--qshot=<png>` — доехать до первого вопроса самой, сохранить кадр и выйти.
- `--shot=<png> --wait=<с>` — кадр через N секунд с зажатым газом.
- `--debug` — печатать состояние машины раз в секунду.
- `--mute` — выключить звук.
- `--season=winter|summer|autumn`, `--lang=ru|en|kk`, `--dark`, `--overview`.

Перекрёстки (`situations/`) не коммитятся: их выгружает `./scripts/godot_dev.sh export` (около 30 минут).
