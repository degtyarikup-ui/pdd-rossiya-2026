# Android: сборка на другом компьютере и установка на телефон

Тестовую сборку можно собрать из репозитория без магазинного ключа подписи.
Она устанавливается как `ru.pdd.pdd_app.dev` («ПДД Россия · Тест»), рядом
с приложением из магазина. Основные команды работают в Bash на macOS и Linux.

## Что установить

| Инструмент | Требование |
| --- | --- |
| Flutter | Проверенная версия — **3.47.4 stable**, Dart **3.13.3**. Минимальное ограничение Dart — `^3.11.4` из `pubspec.yaml` |
| Java | Рекомендуется **JDK 17**; скрипт принимает JDK ≥17, путь — в `JAVA_HOME` |
| Android SDK | SDK Manager, Command-line Tools, Platform Tools (`adb`); путь к SDK — в `ANDROID_HOME` |
| CMake | **3.22.1** внутри Android SDK; устанавливает `setup_android.sh` |
| Git, Bash, Python **3.9+**, curl, unzip | Синхронизация, скрипты сборки и резервная загрузка |
| Godot | **4.7.2 Standard** + шаблоны экспорта той же версии, если нужна 3D-игра |
| FFmpeg (`ffmpeg` и `ffprobe`) | преобразование существующих записей вопросов в общий MP3-каталог игры |

Flutter и Android SDK должны быть установлены на этом компьютере. Не копируйте
`android/local.properties` с чужой машины: `flutter.sdk` и `sdk.dir` в нём —
локальные абсолютные пути.

Пример окружения на macOS с Homebrew JDK 17 и Android Studio:

```bash
export PATH="$HOME/flutter/bin:$PATH"
export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
```

На Linux SDK обычно лежит в `$HOME/Android/Sdk`, на Intel Mac путь Homebrew
JDK отличается. Укажите свои пути и проверьте `java -version`,
`flutter --version`, `adb version`. Скрипт ищет SDK по `android/local.properties`,
`ANDROID_HOME`/`ANDROID_SDK_ROOT`, настройке Flutter и стандартным каталогам.
Если `flutter doctor -v` показывает другую Java, явно выберите установленный
JDK: `flutter config --jdk-dir="$JAVA_HOME"`.
Если настройка SDK в Flutter расходится с `sdk.dir`/окружением, скрипт
остановится до установки пакетов. Выберите нужный SDK командой
`flutter config --android-sdk="$ANDROID_HOME"` и повторите подготовку.

## Первый запуск из свежей копии

```bash
git clone https://github.com/degtyarikup-ui/pdd-rossiya-2026.git "PDD Russia"
cd "PDD Russia"
git pull --rebase origin main

flutter doctor --android-licenses
./scripts/setup_android.sh
flutter doctor -v
flutter pub get
flutter gen-l10n

./scripts/build_dev.sh
```

`setup_android.sh` проверяет Flutter, Java ≥17 и Android SDK, затем устанавливает
недостающий `cmake;3.22.1` через `sdkmanager`. Android Studio → SDK Manager
позволяет поставить Command-line Tools, если `sdkmanager` ещё отсутствует.
Платформа Android, Build Tools и NDK берутся из требований Flutter/Gradle;
их загрузке нужны принятые лицензии и доступ к серверам Android SDK.

Готовый APK: `build/app/outputs/flutter-apk/app-ru-release.apk`.
`build_dev.sh` собирает release APK с `-Pdev`; Flutter debug-режим и тестовый
суффикс пакета — разные вещи. Если `android/key.properties` отсутствует,
dev APK подписывается локальным debug-ключом Android. Обычная магазинная
release-сборка по-прежнему требует ключ владельца.

В `-Pdev` отключены Android-минимизация R8 и удаление неиспользуемых ресурсов:
с встроенным Godot этот этап существенно замедляет повторные сборки.
Flutter/Dart AOT и движок Godot остаются release, `debuggable=false`; APK может
быть больше магазинного. Такая сборка подходит для проверки игры и её FPS,
но не проверяет правила R8 и сохранность Android-ресурсов после удаления.
Перед публикацией проверяйте обычную сборку без `-Pdev`: в ней оба этапа
включены как раньше, в том числе для RuStore.

Для Pixel и других ARM64-телефонов `./scripts/build_dev.sh --arm64`
собирает APK только под эту архитектуру и уменьшает его размер.

После обновления копии через `git pull --rebase origin main` повторите сборку.
`build_dev.sh` автоматически экспортирует Godot перед APK, если движок доступен
или уже есть экспорт игры. При ошибке экспорта сборка APK останавливается:
старый пакет Godot нельзя выдать за текущий Git-коммит. Прямой `flutter build`
по-прежнему требует предварительного `godot_android_assets.sh` вручную.

## Как различать dev-сборки

Основную версию `2.2.3` в `pubspec.yaml` ради тестовой установки не менять.
`build_dev.sh` автоматически задаёт дополнительный Android build number —
число секунд Unix UTC на момент сборки — и `GIT_COMMIT` (короткий SHA исходников).
Внизу «Настроек» отображается, например: `Версия 2.2.3 (1791990000) · b52f22b2`.
Число в скобках различает пересборки, SHA позволяет найти код на GitHub.
Раньше номер содержал только дату и час, поэтому сборки одного часа совпадали.

Для передачи сборки другу и отчёта об ошибке записывать всю строку версии,
модель устройства и способ сборки. Перед сборкой законченные изменения
коммитить и пушить; SHA указывает на коммит, а не на незакоммиченные правки.
Для двух разных сборок выдерживать хотя бы секунду. На dev-установке номер
не относится к магазинному `+61`; магазинный номер меняется при релизе.
На других платформах также передавать `GIT_COMMIT` и отдельный build number
через соответствующий скрипт сборки; не добавлять тестовый суффикс к store version.

## Сборка с 3D-игрой

Движок и экспортированные ресурсы игры не хранятся в Git. После установки
Godot **4.7.2 Standard** и его экспортных шаблонов выполните:

```bash
./scripts/setup_game.sh
./scripts/godot_android_assets.sh
./scripts/build_dev.sh
```

`godot_android_assets.sh` создаёт `android/godot/godot-lib.aar` и
`android/godot/assets/`. Промежуточный Godot APK нужен только для извлечения
ресурсов и экспортируется без подписи; магазинный ключ для этого не нужен.
Без `android/godot/` Flutter-приложение собирается, но Godot-игра недоступна.
Устройство для игры должно быть ARM64. Подробнее — [документация игры](../game/README.md).

Экспорт проверяет журнал на `SCRIPT ERROR` и `ERROR`: Godot иногда возвращает
код успеха даже при ошибке разбора скриптов. При таких ошибках сборка ресурсов
останавливается; подробности сохраняются в `output/godot/android-export.log`.

Android-мост игры находится в Kotlin-файлах
`android/app/src/godot/kotlin/ru/pdd/pdd_app/game/GodotGameActivity.kt` и
`PddHostPlugin.kt`. Их компиляция подключается только при наличии
`android/godot/godot-lib.aar`.

## Если загрузка зависимостей зависает

При проверке 13.10.2026 были подтверждены две отдельные причины:

1. В SDK отсутствовал **CMake 3.22.1**.
2. Java/Gradle зависал на HTTP-запросах к Google Maven, в том числе при
   загрузке `androidx.activity:activity:1.13.0`. На том же компьютере
   запросы через `curl` проходили; большие файлы SDK удалось скачать
   частями по 64 КиБ.

Это ошибки до компиляции Kotlin; они не указывают на ошибку в мосте Godot
и не устанавливают причину по стране пользователя.

Сначала используйте обычные команды. Если воспроизводится тайм-аут загрузки
SDK или Google Maven, включите резервный способ явно:

```bash
./scripts/setup_android.sh --download-fallback
./scripts/build_dev.sh --download-fallback
```

Для CMake скрипт использует официальный репозиторий Android SDK, загрузку
через `curl` частями по 64 КиБ и проверку контрольной суммы из метаданных SDK.
Для Maven на время сборки запускается локальный мост к официальному
Google Maven: Gradle получает зависимости через него, а мост скачивает их
через `curl`. Временные настройки удаляются после завершения сборки.
Проверка TLS не отключается, сторонний Maven-репозиторий не добавляется.

Ошибки Flutter Pub, Maven Central, Gradle Plugin Portal, скачивания самого
Gradle, платформы SDK или NDK разбираются отдельно по URL и тексту ошибки.
Мосту тоже нужен доступ к исходному серверу. Не меняйте версии зависимостей
ради сетевой ошибки; логи сохраняйте в `output/` или `scratch/`.

| Ошибка | Что проверить |
| --- | --- |
| Нет `cmake/3.22.1`, автоматическая загрузка CMake зависла | `setup_android.sh`; при повторном тайм-ауте — `--download-fallback` |
| `Could not HEAD` / `Read timed out` с Google Maven | `build_dev.sh --download-fallback`; если не помогло — URL и ответ `curl` |
| `sdkmanager` не найден | Установить Android SDK Command-line Tools, проверить путь к SDK |
| `Unsupported class file` / несовместимая Java | `java -version`, `JAVA_HOME`, Java, выбранная Flutter в `flutter doctor -v`; рекомендован JDK 17 |
| Не приняты лицензии SDK | `flutter doctor --android-licenses` |
| Нет `android_source.zip` / шаблонов Godot | Установить экспортные шаблоны **4.7.2**, проверить `godot --version` |
| Godot-игра недоступна | Выполнить `godot_android_assets.sh` и пересобрать APK |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | Проверить пакет `.dev` и подпись ранее установленной dev-версии; см. ниже |

## Установка на телефон по Wi-Fi

Первое сопряжение выполняется отдельно для каждого компьютера. На телефоне
включите режим разработчика и «Отладку по Wi-Fi», подключитесь к той же сети,
что и компьютер. Выберите «Подключить устройство с помощью кода сопряжения»:

```bash
adb pair IP:PAIR_PORT
# Введите код с экрана сопряжения телефона.
adb connect IP:CONNECT_PORT
adb devices -l
```

`PAIR_PORT` берётся из окна с кодом. `CONNECT_PORT` — из основного экрана
«Отладка по Wi-Fi»; это другой порт. Вместо `IP` подставьте адрес телефона.
После сопряжения:

```bash
./scripts/install_dev.sh --build
# При тайм-аутах Google Maven:
./scripts/install_dev.sh --build --download-fallback
```

Для уже собранного APK достаточно `./scripts/install_dev.sh`. Скрипт ищет
авторизованный телефон через `adb`/mDNS и сохраняет последний адрес локально
в `.dev-device`. Если автообнаружение не сработало, укажите адрес соединения:

```bash
./scripts/install_dev.sh IP:CONNECT_PORT
```

В `adb devices -l` нужен статус `device`. После перезагрузки телефона порт
может измениться; берите новый адрес с экрана отладки. `.dev-device` и
`.dev-mac` между компьютерами не переносятся.

Для USB включите «Отладку по USB», подключите кабель, подтвердите доступ
компьютера на телефоне и выполните ту же команду `install_dev.sh --build`.
При нескольких подключённых устройствах отключите остальные: скрипт
выбирает первое доступное устройство.

Если ранее установленный пакет `.dev` подписан другим ключом, Android
не разрешит обновление поверх него. Для сохранения данных используйте
тот же локальный ключ подписи, переданный владельцем безопасным способом.
Удаление только тестового приложения позволяет установить APK с новым
ключом, но удалит его локальный прогресс; магазинное приложение имеет
другой пакет и остаётся на телефоне.

## Ключи и локальные файлы

Если `android/key.properties` уже настроен, dev APK использует его подпись.
Ключи для публикации в магазине передаются владельцем отдельно.

`secrets/install_notify_secret.txt` нужен для серверных возможностей
приложения, например ИИ и рейтинга. Без него APK собирается, но эти запросы
не получат доступ к серверу. Скрипт сборки подставляет секрет, если файл
есть. Не публикуйте этот файл, ключ подписи, локальные настройки SDK,
кэш загрузок или журналы с чувствительными данными.

Скрипты проверяются на macOS/Linux. На Windows используйте Android Studio
для установки SDK и обычную команду
`flutter build apk --flavor ru --release --dart-define=COUNTRY=ru -Pdev`,
либо WSL с Linux-версиями Flutter, JDK, SDK и `adb` в одном окружении.
Не смешивайте Windows/Linux пути и серверы `adb`. Резервная загрузка SDK
скриптом на native Windows не поддерживается; автообнаружение телефона
отдельно не проверено. Соединение можно проверить через явный `adb pair`/
`adb connect`, затем установить APK командой `adb install -r <путь-к-APK>`.

Перед коммитом выполняются [проверки проекта](../testing.md):
`flutter analyze` и `flutter test`. Сборка APK дополнительно проверяет
Android-код; наличие подготовленных ресурсов Godot требуется для проверки
обоих Kotlin-файлов моста игры.
