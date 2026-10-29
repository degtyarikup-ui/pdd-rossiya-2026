# Выпуск в сторы через API

Google Play, App Store Connect и RuStore публикуются одной командой на сторе,
без браузера и ручной загрузки файлов. Проверено при выпуске 2.2.7 (69)
29.10.2026.

```bash
/usr/bin/python3 tools/store_release/publish.py status                     # что сейчас в сторах
/usr/bin/python3 tools/store_release/publish.py play     <app.aab> tools/store_release/notes/<версия>.json
/usr/bin/python3 tools/store_release/publish.py appstore <build>   tools/store_release/notes/<версия>.json
/usr/bin/python3 tools/store_release/publish.py rustore  <app.apk> tools/store_release/notes/<версия>.json
```

`notes/<версия>.json` — «Что нового» на ru/en/kk, не длиннее 500 символов
(ограничение Google Play). App Store берёт текст для языков своей версии,
RuStore — русский. Все сторы публикуют версию автоматически после одобрения.

## Порядок выпуска

1. `scripts/build.sh ru aab`, `scripts/build.sh ru rustore-apk`, `scripts/build.sh ru ipa`.
   `ipa` сам загружает сборку в App Store Connect через аккаунт Xcode.
   Номер сборки должен быть больше всех загруженных в App Store Connect,
   а не только опубликованных.
2. `publish.py play` — загрузка AAB, релиз в production со статусом
   `completed`, коммит правки. Правки уходят на проверку сразу; параметр
   `changesNotSentForReview` в этом состоянии консоли Google отклоняет.
3. `publish.py appstore` — ждёт обработки сборки Apple (до 90 минут),
   привязывает её к редактируемой версии (публикация `AFTER_APPROVAL`),
   заполняет «Что нового» и отправляет заявку на проверку.
4. `publish.py rustore` — черновик версии (остальные поля копируются из
   активной), загрузка APK, отправка на модерацию, `publishType: INSTANTLY`.
   Прокси RuStore может ответить 503 на загрузку, которая на самом деле
   прошла; тогда скрипт создаёт новый черновик (он заменяет старый) и
   грузит заново — иначе модерация отклонит версию с двумя основными APK.

## Ключи

В репозитории ключей нет: он публичный. Скрипт читает их из Связки ключей
macOS (login) и не печатает:

| Стор | Служба в Связке ключей | Учётная запись |
| --- | --- | --- |
| App Store Connect | `codex.pdd-russia.appstoreconnect` | Key ID `G3JJFBDVMQ`, Issuer ID в скрипте |
| Google Play | `codex.pdd-russia.googleplay` | сервисный аккаунт `codex-releases@…`, права Admin |
| RuStore | `codex.pdd-russia.rustore` | keyId `2351034241` |

Подключение настроено 28.10.2026; описание и проверочные клиенты —
`~/Library/Application Support/CodexIntegrations/*/README.md`. RuStore
работает на сертификатах Russian Trusted CA: скрипт использует
`CodexIntegrations/rustore/ca-bundle.pem` и не отключает проверку TLS.
На другом компьютере ключи нужно заново занести в Связку ключей
(`security add-generic-password -s <служба> -a <учётная запись> -w`).
