# Вход на pdd-drive.app при подготовке переезда

Новый адрес использует существующие аккаунты и тот же API. AccountState, KV,
идентификаторы провайдеров и Премиум не копируются и не переключаются. Статический
Worker `pdd-domain-migration-preview` получает только ASSETS; основной Worker
`pdd-install-notifier` для этого шага развёртывать не требуется.

## Что требуется в кабинетах провайдеров

Добавлять адреса к существующим клиентам, сохраняя все прежние настройки:

| Провайдер | Существующий клиент | Добавление |
| --- | --- | --- |
| Google | `PDD Drive Web`, client ID из `AuthService.googleWebClientId` | JavaScript origin `https://pdd-drive.app` |
| Яндекс | `94aa539db4634e44bf0b209d9a2205d2` | `https://pdd-drive.app/app/yandex-auth.html` и тот же URI с `?flow=redirect` |
| Apple | Services ID `ru.pdd.pddapp.auth`, primary App ID `ru.pdd.pddApp` | Domain `pdd-drive.app`, Return URL `https://pdd-drive.app/auth/apple/callback` |

Telegram использует прежнего бота `pdda_bot`, две существующие операции
`/api/auth/telegram/request` и `/api/auth/telegram/check` и одноразовую ссылку;
нового бота/вебхука на `.app` не создаём.

Яндекс читает профиль только через прежний GET
`https://login.yandex.ru/info?format=json`; в режиме входа разрешён этот точный
адрес и метод, без дополнительных параметров.

Google остаётся GIS TokenClient с прежними scopes. Яндекс вычисляет callback
относительно текущей вкладки. Apple выбирает новый фиксированный callback только
на точном HTTPS origin `pdd-drive.app`; остальные сборки сохраняют старый URL.
Callback на новом статическом Worker принимает ограниченную Apple form_post
форму и возвращает результат только на `https://pdd-drive.app/app/?oauth=2` во
фрагменте. Личность по-прежнему проверяет основной API. State/nonce принадлежат
исходной вкладке, одноразовые, срок 10 минут.

## Явное включение режима входа

Обычный режим `stage_site.py` остаётся полностью изолированной гостевой копией.
Режим входа требует `--enable-account-login` и у подготовки статики, и у
подготовки хоста. Исходник — отдельная копия ранее сохранённого сайта с новой
сборкой Flutter в `app/`; рабочий сайт и исходный архив не изменяются.

```bash
python3 tools/domain_migration/stage_site.py \
  --source <separate-source> --destination <new-stage> \
  --origin https://pdd-drive.app --source-revision <git-sha> --enable-account-login
python3 tools/domain_migration/prepare_preview_host.py \
  --staged-site <new-stage> --output-dir <new-host> --enable-account-login
```

Точные CLI-флаги источника/назначения проверять через `--help`.
Развёртывать только конфигурацию подготовленного хоста, без `deploy_web.sh` и
без основного server/install-notifier/wrangler.toml.

Этот режим разрешает браузеру существующие auth/session/logout, user/status,
user/sync и user/progress/sync/read, чтение места в рейтинге `/api/game/best`, а также две операции Telegram на двух прежних API origins. Это **реальные
аккаунты и облачный прогресс**, поэтому режим не является закрытым стендом
восстановления. Действия после входа синхронизируются с рабочими аккаунтами.
Оплата, удаление аккаунта, аналитика и прочие API в тестовой копии заблокированы.
Ссылки на тарифы/возврат оплаты остаются на `.ru`. Platega и его зарегистрированные
адреса не изменяются. Noindex/no-store сохраняются; workers.dev вход отключён.

Локальный/гостевой прогресс старого origin `.ru` браузер автоматически не
переносит. Этот шаг не добавляет мост локальных данных и не переводит старых
пользователей на новый домен.

## Проверка и откат

- Полные Flutter tests/analyze и backend security; тесты web_oauth_state,
  apple-web-callback и stage/host/preview_worker.
- На `.app` проверить Google GIS SDK и отсутствие CSP-ошибок, начало всех трёх
  OAuth flows и возврат в исходную вкладку. Реальный вход каждым провайдером
  проверить владельцу тем же способом, которым создан прежний аккаунт.
- После входа сверить идентификатор аккаунта, срок/источник Premium, AB/CD
  прогресс и повторный вход. Не создавать оплаты для проверки авторизации.
- До/после сравнить deployment основного API и рабочий HTML `.ru`; сохранить
  предыдущий version ID статического Worker для обратного переключения.
- Откат касается только версии Worker `pdd-domain-migration-preview`; удалять
  аккаунты, очищать browser storage или восстанавливать старую базу не нужно.

Если кабинет провайдера недоступен или настройка ещё не сохранена, соответствующий
провайдер не считать запущенным. Отдельно фиксировать проверку кода/публикацию
страниц/регистрацию адресов и фактически завершённый вход.
