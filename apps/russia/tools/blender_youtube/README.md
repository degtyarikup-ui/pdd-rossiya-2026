# Горизонтальный Blender-пилот

Новый формат по запросу владельца 09.11.2026: режиссированная автомобильная
история в цветном городе, с уровня улицы. Без вида сверху, белого макета,
викторины, отсчёта и прежнего шаблона Shorts. Основа — A/B, билет 39, вопрос 14;
красная поворачивает налево и уступает синей справа по пункту 13.11.

Монтаж: 82 секунды, 24 кадра/с, 1920×1080. В сцене 12 монтажных камер,
боковое сопровождение, подъезд, общий план с тротуара, взгляд водителя направо,
проезд синей и левый поворот красной. Геометрия, материалы, свет и движение
сохраняются в `.blend`; итоговые медиа находятся в `output/blender_youtube/pilot_001/`.
Пробные кадры не означают, что полный ролик прошёл проверку.

Стёкла кузова используют тонкую прозрачную поверхность с небольшим отражением:
замена её сплошным преломляющим объёмом давала чёрный обзор из салона.
При проверке этого плана смотреть кадры на 42, 43, 47 и 52,9 секунды.
У импортированных колёс Ferrari сохранён исходный поворот осей и включён
режим Euler, соответствующий запечённым ключам вращения.

Все команды ниже выполняются из основного репозитория `main/`.
После переноса приложения исходники инструмента лежат в `apps/russia/tools/blender_youtube/`.

1. Скачать модели по адресам в `assets.json` в рабочую папку `assets/`.
   Распаковать BMW ZIP в `assets/bmw/`. Условия и обязательные авторские
   упоминания сохранены в `assets.json`; их включать в описание видео.
2. Подготовить BMW:

   ```sh
   /Applications/Blender.app/Contents/MacOS/Blender --disable-autoexec -b output/blender_youtube/pilot_001/assets/bmw/bmw27/bmw27_cpu.blend --python apps/russia/tools/blender_youtube/prepare_bmw.py
   ```

3. Записать и проверить озвучку (используется существующая конфигурация Google Cloud):

   ```sh
   python3 apps/russia/tools/blender_youtube/prepare_audio.py
   ```

4. Собрать сцену и проверить ключевые кадры:

   ```sh
   /Applications/Blender.app/Contents/MacOS/Blender -b --python apps/russia/tools/blender_youtube/scene.py -- --preview --samples 32 --cpu
   ```

5. Рендерить с возможностью продолжения и собрать MP4:

   ```sh
   /Applications/Blender.app/Contents/MacOS/Blender -b output/blender_youtube/pilot_001/pdd_youtube_001.blend --python apps/russia/tools/blender_youtube/render.py -- --samples 32
   python3 apps/russia/tools/blender_youtube/finish.py
   ```

`finish.py` сохраняет отдельные SRT и дорожку, добавляет отключаемые субтитры в MP4,
проверяет полное декодирование, размер, число кадров, длительность и SHA-256.
Перед выдачей дополнительно проверить все склейки, направления движения,
видимость условий с места водителя, отсутствие пересечений и звучание речи.
Публикация на YouTube этим инструментом не выполняется.

## Быстрый вариант EEVEE

После отказа владельца от многочасового Cycles-рендера создан отдельный проект
`pdd_youtube_001_eevee.blend`. Исходный `.blend` и 812 кадров Cycles сохранены.
Используются запечённое непрямое освещение улицы и упакованная HDR-панорама
для отражений. Динамические cubemap-пробы, трассировка экранных лучей,
микрорельеф и глубина резкости отключены; заполнение светом не строит дорогие
мягкие тени. Тени солнца и контактные тени под машинами остаются.
Это компромисс по свету и отражениям, а не идентичный Cycles результат.
Разрешение 1920×1080 и частота 24 fps сохранены.

Команды из `main/` (каждая следующая — после успешного завершения предыдущей):

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b output/blender_youtube/pilot_001/pdd_youtube_001.blend --python-exit-code 2 --python apps/russia/tools/blender_youtube/bake_environment.py
/Applications/Blender.app/Contents/MacOS/Blender -b output/blender_youtube/pilot_001/pdd_youtube_001.blend --python-exit-code 2 --python apps/russia/tools/blender_youtube/prepare_eevee.py
/Applications/Blender.app/Contents/MacOS/Blender -b output/blender_youtube/pilot_001/pdd_youtube_001_eevee.blend --python-exit-code 2 --python apps/russia/tools/blender_youtube/render_eevee.py -- --preview
python3 apps/russia/tools/blender_youtube/make_preview.py
```

Тест — 144 настоящих кадра, 6 секунд без звука: сопровождение, поворот взгляда
из салона, левый поворот. Копия `pdd_youtube_001_fast_test.mp4` сохраняется
на рабочий стол. Замеры — `fast_preview_timing.json`; прогноз полного времени
делать по всем трём планам, не по первому кадру.

Для полного рендера заменить `--preview` на `--full`, затем:

```sh
python3 apps/russia/tools/blender_youtube/finish.py --frames-dir frames_eevee --output-stem pdd_youtube_001_eevee
```

Кадры EEVEE не смешивать с Cycles: материалы и свет отличаются.
После изменения сцены использовать новую папку кадров либо явно архивировать
предыдущий тест: возобновление не проверяет соответствие кадров версии сцены.
