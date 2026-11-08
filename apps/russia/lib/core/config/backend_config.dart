/// Единственная серверная точка приложения — Cloudflare Worker, который
/// пересылает события в Telegram (исходники: `server/install-notifier/`).
///
/// Через него идут: пинг о новой установке ([InstallReporter]) и жалобы на
/// вопросы ([QuestionReportService]). Токен бота живёт в секрете воркера и в
/// приложение не попадает.
///
/// Использование режимов отправляется пакетами через UsageReporter;
/// обучение продолжает работать офлайн.
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

  /// Запасной адрес того же воркера на нашем домене. У части операторов
  /// маршрут до `*.workers.dev` нестабилен — тогда вход и отправка отчётов
  /// автоматически пробуют этот адрес. Пока DNS для него не настроен, запрос
  /// к нему мгновенно завершается ошибкой, и приложение остаётся на основном.
  static const String notifierFallbackUrl = String.fromEnvironment(
    'INSTALL_NOTIFY_FALLBACK_URL',
    defaultValue: 'https://api.pdd-drive.app',
  );

  static const String _defaultNotifierUrl =
      'https://pdd-install-notifier.sergei-pdd.workers.dev';

  /// Адреса воркера по порядку: основной, затем запасной. Запасной
  /// подключается только к боевому воркеру: тестовая сборка с другим адресом
  /// не должна случайно писать в боевой.
  static List<String> get notifierHosts => [
    notifierUrl,
    if (notifierUrl == _defaultNotifierUrl &&
        notifierFallbackUrl.startsWith('https://') &&
        notifierFallbackUrl != notifierUrl)
      notifierFallbackUrl,
  ];

  /// Настроен ли адрес (иначе сетевые функции просто молчат).
  static bool get hasNotifier => notifierUrl.startsWith('https://');
}
