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
  final query = Uri.base.queryParameters;
  final ref = query['ref']?.split('_');
  var source = (query['utm_source'] ?? ref?.first ?? '').toLowerCase();
  var method = 'web_utm';
  if (source.isEmpty && web.document.referrer.isNotEmpty) {
    final host = Uri.tryParse(web.document.referrer)?.host ?? '';
    for (final entry in const {
      'threads.net': 'threads',
      'threads.com': 'threads',
      'instagram.com': 'instagram',
      'youtube.com': 'youtube',
      't.me': 'telegram',
      'vk.com': 'vk',
    }.entries) {
      if (host == entry.key || host.endsWith('.${entry.key}')) {
        source = entry.value;
      }
    }
    method = 'web_referrer';
  }
  source =
      const {
        'th': 'threads',
        'ig': 'instagram',
        'yt': 'youtube',
        'tt': 'tiktok',
        'tg': 'telegram',
      }[source] ??
      source;
  if (!const {
    'threads',
    'instagram',
    'youtube',
    'tiktok',
    'telegram',
    'vk',
    'google',
    'yandex',
    'direct',
    'other',
  }.contains(source)) {
    return {};
  }
  final campaign =
      query['utm_campaign'] ??
      (ref != null && ref.length > 1 ? ref.skip(1).join('_') : '');
  return {
    'marketingSource': source,
    'attributionMethod': method,
    if (RegExp(r'^[A-Za-z0-9._-]{1,64}$').hasMatch(campaign))
      'marketingCampaign': campaign,
  };
}
