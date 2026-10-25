import 'dart:convert';

import 'package:pdd_app/data/services/acquisition_fields.dart';
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

Map<String, String> browserAcquisitionFields() {
  // The landing and app share this first touch on pdd-drive.ru. Reading it
  // before the current URL preserves an article/search visit through OAuth
  // redirects, page reloads, and later direct visits.
  final stores = [
    () => web.window.localStorage,
    () => web.window.sessionStorage,
  ];
  for (final store in stores) {
    try {
      final saved = store().getItem(AcquisitionFields.storageKey);
      if (saved != null) {
        final decoded = jsonDecode(saved);
        if (decoded is Map) {
          final first = AcquisitionFields.sanitize(decoded);
          if (first.isNotEmpty) return first;
        }
      }
    } catch (_) {}
  }
  final first = AcquisitionFields.fromBrowser(Uri.base, web.document.referrer);
  for (final store in stores) {
    try {
      store().setItem(AcquisitionFields.storageKey, jsonEncode(first));
    } catch (_) {}
  }
  return first;
}

/// Возврат с формы оплаты на сайте: `?pay=done|failed&order=<id>`.
/// Параметры сразу убираются из адреса, чтобы перезагрузка страницы не
/// показывала итог оплаты повторно.
({String result, String order})? takePaymentReturn() {
  final base = Uri.base;
  final result = base.queryParameters['pay'];
  final order = base.queryParameters['order'];
  if (result == null || order == null) return null;
  final rest = Map.of(base.queryParameters)
    ..remove('pay')
    ..remove('order');
  final query = rest.isEmpty ? '' : '?${Uri(queryParameters: rest).query}';
  final fragment = base.hasFragment ? '#${base.fragment}' : '';
  web.window.history.replaceState(null, '', '${base.path}$query$fragment');
  return (result: result, order: order);
}
