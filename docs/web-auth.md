# Вход на сайте и iOS

Продакшен: https://pdd-drive.ru/app/.

## Яндекс ID

Существующее приложение «ПДД: билеты и экзамен», client ID
`94aa539db4634e44bf0b209d9a2205d2` сохранено: менять его нельзя без
проверки привязки аккаунтов и премиума. Сервер проверяет client ID токена.

В кабинете владельца https://oauth.yandex.ru/ зарегистрированы Redirect URI:

- `ru.pdd.pddapp://oauth` — существующий мобильный WebView;
- `https://oauth.yandex.ru/verification_code` — отладочный адрес;
- `https://pdd-drive.ru/app/yandex-auth.html` — сайт.

Ошибка 400 «redirect_uri не совпадает с Callback URL» исправляется
в кабинете Яндекс ID. Платформа iOS включена с AppId
`6T66V45XC7.ru.pdd.pddApp` и App Store URL
`https://apps.apple.com/ru/app/id6792369533`.

Сайт открывает OAuth в той же вкладке. `web/yandex-auth.html` убирает
токен из истории и возвращает его приложению во фрагменте адреса.
Legacy-передача в opener сохранена для уже открытых старых вкладок.

## Apple ID

В Apple Developer (команда `6T66V45XC7`) создан Services ID
`ru.pdd.pddapp.auth`, связанный с primary App ID `ru.pdd.pddApp`.
Домены: `pdd-drive.ru`, `pdd-install-notifier.sergei-pdd.workers.dev`.
Точный Return URL:

```
https://pdd-install-notifier.sergei-pdd.workers.dev/auth/apple/callback
```

Сайт использует OAuth redirect (`code id_token`, `form_post`) без
всплывающего окна и зависимости от Apple JS SDK. Apple POST принимает
`server/install-notifier/apple_web_callback.js` и возвращает браузер
на фиксированный адрес сайта с результатом во фрагменте. Этот обработчик
не создаёт сессию и не записывает профиль.

## Проверка результата

Оба веб-входа сохраняют только случайный `state`, время начала и Apple
`nonce` в sessionStorage исходной вкладки, на 10 минут и один раз.
Flutter удаляет фрагмент с credentials до запуска маршрутизации и
аналитики, проверяет state/provider/возраст; для Apple также nonce.
Идентификатор Apple берётся из `sub` (в вебе userIdentifier отсутствует).
`/api/auth/session` проверяет подпись, issuer, audience и срок токена
Apple либо токен Яндекса, и выдаёт сессию приложения.

Полный вход проверять с реальным аккаунтом на iPhone; пароли и токены
не сохранять в логах. Регрессии: `test/web_oauth_state_test.dart`,
`test/auth_jwt_claim_test.dart`, `test/auth_login_recovery_test.dart`,
`server/install-notifier/test-apple-web-callback.mjs`.

После правок обработчика требуется `npx wrangler deploy` из
`server/install-notifier`; после Dart/HTML — `./scripts/deploy_web.sh ru`.
