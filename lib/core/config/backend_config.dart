/// Единственная серверная точка приложения — Cloudflare Worker, который
/// пересылает события в Telegram (исходники: `server/install-notifier/`).
///
/// Через него идут: пинг о новой установке ([InstallReporter]) и жалобы на
/// вопросы ([QuestionReportService]). Токен бота живёт в секрете воркера и в
/// приложение не попадает.
///
/// Всё остальное в приложении работает офлайн и никуда ничего не отправляет.
library;

class BackendConfig {
  BackendConfig._();

  /// Адрес воркера. Переопределяется при сборке:
  /// `--dart-define=INSTALL_NOTIFY_URL=...`
  static const String notifierUrl = String.fromEnvironment(
    'INSTALL_NOTIFY_URL',
    defaultValue: 'https://pdd-install-notifier.sergei-pdd.workers.dev',
  );

  /// Общий секрет для защиты эндпоинта от постороннего спама. Если на воркере
  /// задан SHARED_SECRET — собирать приложение с тем же значением через
  /// `--dart-define=INSTALL_NOTIFY_SECRET=...`.
  static const String notifierSecret = String.fromEnvironment(
    'INSTALL_NOTIFY_SECRET',
    defaultValue: '',
  );

  /// Настроен ли адрес (иначе сетевые функции просто молчат).
  static bool get hasNotifier => notifierUrl.startsWith('https://');
}
