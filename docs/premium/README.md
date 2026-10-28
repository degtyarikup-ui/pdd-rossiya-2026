# Вход, оплата и Премиум — карта и инварианты

Самая чувствительная часть проекта: ошибка здесь стоит денег или доступа
людей к купленному. Перед правкой прочитать этот файл целиком; после правки
прогнать все проверки из раздела «Как проверить».

## Как это устроено

```
Приложение (Flutter)                          Воркер (Cloudflare, server/install-notifier)
──────────────────────                        ──────────────────────────────────────────
AuthService ── вход Google/Яндекс/Apple ──►   /api/auth/*        → сессия, user.id = <provider>_<sub>
PremiumService ─ syncWithServer ──────────►   /api/user/status   → isPremium / premiumExpiresAt / premiumSource
IapService ─ покупка в сторе ─► recordPurchase ► /api/user/purchase → store_verification.js проверяет чек
PremiumService.startWebPayment ───────────►   /api/user/pay-intent → payments.js → Platega (СБП)
PendingPayment + checkPendingPayment ─────►   /api/user/pay-check  → срок только по статусу от Platega
                                              /api/pay/platega/callback → settleOrder
```

Премиум привязан к **аккаунту на сервере**, не к устройству. Google, Яндекс и
Apple — разные аккаунты.

## Файлы

| Где | Что |
| --- | --- |
| `lib/data/services/auth_service.dart` | Вход/выход/удаление аккаунта, все провайдеры |
| `lib/data/services/auth_session_store.dart` | Хранение сессии (учётки провайдеров не пишутся в prefs) |
| `lib/data/services/web_oauth_*.dart`, `yandex_native_auth.dart` | Веб-OAuth (state-проверка), нативный Яндекс |
| `lib/data/services/premium_service.dart` | Статус Премиума, лимиты бесплатного режима, веб-оплата |
| `lib/data/services/iap_service.dart` | Покупки App Store / Google Play, восстановление |
| `lib/data/services/payment_mode.dart` | Какой способ оплаты показать (по сборке и стране) |
| `lib/data/services/pending_payment.dart` | Незавершённая СБП-оплата на Android |
| `lib/data/services/device_region.dart` | Страна устройства (сеть/SIM/локаль, **не IP**) |
| `lib/core/config/store_config.dart` | `--dart-define=STORE=play|rustore` |
| `lib/presentation/widgets/premium_paywall_sheet.dart`, `premium_benefits_screen.dart`, `premium_plans_sheet.dart`, `web_payment_dialog.dart`, `web_payment_return.dart`, `subscription_management_sheet.dart`, `premium_granted_dialog.dart` | Экран преимуществ, выбор тарифа и экраны оплаты |
| `lib/presentation/widgets/auth_modal_sheet.dart`, `auth_provider_button.dart`, `yandex_*`, `google_web_sign_in_button*` | Экраны входа |
| `web_landing/ru/tarify/`, `pay-done/` | Тарифы на сайте и возврат после оплаты |
| `server/install-notifier/account_state.js`, `account_maintenance.js` | Авторитетное хранилище аккаунта, атомарный журнал, сверка |
| `server/install-notifier/entitlements.js` | Сроки Премиума по источникам |
| `server/install-notifier/payments.js` | Тарифы `WEB_TARIFFS`, Platega, подтверждение оплаты |
| `server/install-notifier/store_verification.js`, `purchase_claims.js` | Проверка чеков сторов |
| `docs/premium/web-payments-launch.md` | Запуск веб-оплаты, секреты, устройство |
| `docs/premium/account-state-rollout.md` | DO миграция, контракты безопасности и порядок выпуска |
| `docs/premium/web-auth.md` | Веб-вход |
| `docs/premium/api-fallback.md` | Запасной адрес сервера и повторы входа |
| `docs/premium/error-messages.md` | Тексты ошибок для пользователя и сообщения в Telegram |
| `docs/premium/subscription-fix-2026-10-02.md` | История исправления подписок |

## Инварианты (нарушать нельзя)

1. Сроки пишутся только через `setEntitlement` / `extendEntitlement`
   (`entitlements.js`), итог — самый дальний срок из источников
   `appstore | googleplay | web | admin_grant`. Поля `isPremium` и т.п.
   напрямую не трогать.
2. Веб-оплата начисляет срок **только** по статусу, перечитанному у Platega,
   никогда по параметрам возврата или колбэка.
3. iOS — только IAP. В iOS-сборке не должно быть ссылок на оплату на сайте.
4. Android, Google Play: СБП только для России (страна устройства по
   `DeviceRegion.countryCode` или страна аккаунта Play по
   `DeviceRegion.playCountry`; решает `currentAndroidPaymentModes`),
   остальным — Play Billing. RuStore (`STORE=rustore`) — СБП для
   всех, Play Billing не используется.
5. Покупка сохраняет аккаунт того, кто её начал (`premium_owner_id`): вход
   другим аккаунтом не переносит Премиум.
6. Без секрета доступ закрывается, а не открывается. Значений по умолчанию
   для ключей нет (репозиторий публичный).
7. Веб-OAuth принимается только во вкладке, которая начала вход; личность
   подтверждает сервер.

8. Все изменения аккаунта проходят через его `AccountState`; профиль, прогресс,
   начисление и `payment_ledger` фиксируются транзакционно. KV — проекция,
   её нельзя использовать для перезаписи авторитетного профиля.
9. Квоты ИИ проверяет сервер атомарно; Premium и личность берутся из сессии,
   не из полей запроса. Ключ приложения не заменяет сессию для свободного чата.
10. Новый App Store claim требует серверный `appAccountToken`; legacy-чек
    без UUID не привязывается первому обратившемуся. Retained Apple auth token
    не выдаётся клиенту, при удалении отзывается либо явно требуется ручной отзыв.

## Как проверить

Вход в Премиум сохраняет контракт `PremiumPaywallSheet.show → Future<bool?>`:
сначала открываются преимущества, по кнопке — отдельный лист тарифов.
Закрытие листа без результата возвращает к преимуществам; успешная покупка
или восстановление (`true`) и открытие СБП в Android-браузере (`false`)
закрывают весь экран. В профиле только два состояния карточки: синий без
Премиума и салатовый с Премиумом; активная карточка открывает управление
подпиской. Дневной остаток карточек на её оформление не влияет.

Кнопка закрытия преимуществ привязана к фактической ширине страницы через
`LayoutBuilder`, а не к ширине всего браузера из `MediaQuery`. Это важно для
веб-оболочки с ограниченной шириной: иначе крестик оказывается за её пределами.
Escape закрывает преимущества, когда это текущий маршрут и лист тарифов
не открыт; у листа сохраняются собственные правила закрытия и блокировки
во время оплаты. Регрессия — `test/premium_web_navigation_test.dart`.

Графика — локальные ассеты Figma в `assets/images/premium/`. Растровые лучи
сохраняют blur исходных SVG; вращается только отдельный декоративный слой
(80 секунд на оборот), при уменьшении анимации и скрытии экрана он остановлен.
Рейтинг 4,7 и доля сдавших 96,8% подтверждены владельцем 23.10.2026.
Лимиты сервисов не меняются: до 200 ИИ-разборов в сутки, безлимитные
заезды «Живого города», русская студийная озвучка и лента.
Текстовые акценты преимуществ повторяют макет: белый и белый с непрозрачностью
40%, одинаковые кегль и жирность. Подписи о бесплатных билетах нет ни на
экране преимуществ, ни в листе тарифов; условия оплаты остаются рядом с кнопкой.

Движение — `premium_motion.dart`: преимущества появляются за 680 мс короткой
последовательностью fade/подъёма, машина въезжает справа за 760 мс при открытии
профиля. При открытии преимуществ рейтинг растёт от 1,0 до 4,7, доля сдавших —
от 1,0% до 96,8% за 1,1 секунды. Ширина чисел фиксирована, для скринридера
сразу доступны итоговые показатели. Звезда — #FFEA00, закрытие — общая кнопка 40×40.
Нажатие слегка уменьшает кнопку/карточку без задержки действия; при
начале прокрутки эффект отменяется. Текст и расположение элементов не меняются
во время движения. Уменьшение анимации сразу показывает конечное состояние,
останавливает лучи и отключает масштабирование при нажатии.

UI-регрессии: `premium_motion_test.dart`, `premium_redesign_test.dart`,
`premium_banner_redesign_test.dart`,
`premium_banner_locale_test.dart`, `paywall_price_placeholder_test.dart`,
`premium_product_loading_test.dart`, `premium_plans_busy_test.dart`,
`games_hub_city_entry_test.dart`.

```bash
flutter test test/premium_service_test.dart test/premium_offline_session_test.dart \
  test/premium_granted_dialog_test.dart test/iap_recovery_test.dart \
  test/iap_account_owner_test.dart test/verified_purchase_test.dart \
  test/payment_mode_test.dart test/pending_payment_test.dart \
  test/auth_jwt_claim_test.dart test/auth_login_recovery_test.dart \
  test/auth_attempt_lifecycle_test.dart test/progress_outbox_test.dart \
  test/auth_provider_button_test.dart test/auth_startup_sync_test.dart \
  test/web_oauth_state_test.dart test/yandex_native_auth_test.dart
cd server/install-notifier && npm run test:security
```

Тестовая СБП-сборка не из России: `DEVICE_REGION=RU ./scripts/install_dev.sh --build`.

## Диагностика СБП

Источник начисления `web` означает СБП через Platega, а не покупку на сайте.
В админке он подписан «СБП (Platega)». Место начала оплаты берётся из
`pay_order.client` (`android` / `web`), в аналитике используется та же платформа.
Telegram показывает место начала, тариф, аккаунт, почту чека, срок СБП,
номера заказа и транзакции, время подтверждения МСК.

Новые клиенты передают `InstallReporter.clientMetadata()` при создании заказа;
сервер сохраняет ограниченный снимок в `pay_order.context`. Для старых клиентов
данные устройства берутся из профиля только при совпадении платформы и явно
помечаются как данные последнего профиля. При подтверждении профиль повторно
не используется для определения устройства покупки. В старых заказах без
`client` место начала неизвестно; Android в профиле сам по себе его не доказывает.
Проверки этого контракта — `test-payments.mjs`.

При повторном нажатии покупки для товара с уже полученной, но ещё не
подтверждённой/завершённой транзакцией клиент повторяет её проверку, а не
открывает новую оплату. Исходный владелец сохраняется; завершение в магазине
происходит только после серверного подтверждения. Защита использует очередь
текущего процесса; после перезапуска восстановление зависит от доставки
транзакции магазином. Регрессия — `test/iap_recovery_test.dart`.
