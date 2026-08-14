import 'package:web/web.dart' as web;

/// Браузер/платформа напрямую из `navigator` — БЕЗ device_info_plus.
///
/// device_info_plus/package_info_plus на вебе полагаются на регистрацию
/// плагина через `dart:ui_web`'s bootstrapEngine (`registerWith` выставляет
/// `Platform.instance`). На проде (pdd-drive.ru, GitHub Pages/Fastly) эта
/// регистрация надёжно НЕ срабатывает (`MissingPluginException`), хотя
/// локально (`flutter build web` + локальный сервер) работает без проблем —
/// похоже на баг совместимости Flutter Web SDK с конкретным хостингом.
/// Прямое чтение `navigator` в обход плагина не зависит от этой регистрации.
Map<String, String> browserInfoFields() {
  final nav = web.window.navigator;
  return {
    'device': _browserNameFromUserAgent(nav.userAgent),
    'os': nav.platform,
  };
}

String _browserNameFromUserAgent(String ua) {
  if (ua.contains('Edg/')) return 'Edge';
  if (ua.contains('OPR/') || ua.contains('Opera')) return 'Opera';
  if (ua.contains('YaBrowser')) return 'Yandex Browser';
  if (ua.contains('Firefox/')) return 'Firefox';
  if (ua.contains('Chrome/') && !ua.contains('Chromium')) return 'Chrome';
  if (ua.contains('Safari/') && !ua.contains('Chrome')) return 'Safari';
  return 'Browser';
}
