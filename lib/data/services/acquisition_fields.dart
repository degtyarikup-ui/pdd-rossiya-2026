/// Bounded first-touch metadata shared by web and native acquisition readers.
/// Store installation source is a separate field: a missing referral is never
/// evidence that a user searched a store.
class AcquisitionFields {
  AcquisitionFields._();

  static const storageKey = 'pdd_acquisition_v2';
  static const _sources = {
    'threads',
    'instagram',
    'youtube',
    'tiktok',
    'telegram',
    'vk',
    'google',
    'yandex',
    'bing',
    'duckduckgo',
    'chatgpt',
    'perplexity',
    'copilot',
    'gemini',
    'claude',
    'direct',
    'other',
    'google_play_organic',
  };
  static const _methods = {
    'play_referrer',
    'play_organic',
    'rustore_referrer',
    'web_utm',
    'web_referrer',
  };

  static String source(String raw) {
    final value = raw.trim().toLowerCase();
    final normalized =
        const {
          'th': 'threads',
          'thread': 'threads',
          'ig': 'instagram',
          'insta': 'instagram',
          'yt': 'youtube',
          'tt': 'tiktok',
          'tg': 'telegram',
          'vkontakte': 'vk',
          'chatgpt.com': 'chatgpt',
          'chat.openai.com': 'chatgpt',
          'perplexity.ai': 'perplexity',
        }[value] ??
        value;
    return _sources.contains(normalized) ? normalized : '';
  }

  static String token(String? raw) {
    final value = raw ?? '';
    return RegExp(r'^[A-Za-z0-9._-]{1,64}$').hasMatch(value) &&
            !const {'__proto__', 'constructor', 'prototype'}.contains(value)
        ? value
        : '';
  }

  static String path(String? raw) {
    if (raw == null || !raw.startsWith('/') || raw.startsWith('//')) return '';
    final value = raw.split(RegExp(r'[?#]')).first;
    if (value.length > 240 || RegExp(r'[\x00-\x20\\<>]').hasMatch(value)) {
      return '';
    }
    return value;
  }

  static String host(String? raw) {
    final value = (raw ?? '').toLowerCase();
    if (value.length > 160 ||
        !RegExp(r'^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$').hasMatch(value) ||
        value.contains('..')) {
      return '';
    }
    return value;
  }

  static Map<String, String> sanitize(Map<Object?, Object?> raw) {
    final channel = source('${raw['marketingSource'] ?? ''}');
    if (channel.isEmpty) return {};
    final method = '${raw['attributionMethod'] ?? ''}';
    return {
      'marketingSource': channel,
      if (_methods.contains(method)) 'attributionMethod': method,
      for (final key in [
        'marketingCampaign',
        'marketingMedium',
        'marketingContent',
      ])
        if (token('${raw[key] ?? ''}').isNotEmpty)
          key: token('${raw[key] ?? ''}'),
      if (path('${raw['landingPage'] ?? ''}').isNotEmpty)
        'landingPage': path('${raw['landingPage'] ?? ''}'),
      if (host('${raw['referrerHost'] ?? ''}').isNotEmpty)
        'referrerHost': host('${raw['referrerHost'] ?? ''}'),
    };
  }

  static Map<String, String> fromQuery(String raw, String method) {
    try {
      final params = Uri.splitQueryString(raw);
      final ref = params['ref']?.split(RegExp(r'[_:-]'));
      var channel = source(params['utm_source'] ?? ref?.first ?? '');
      var resolvedMethod = method;
      // Google Play's organic marker covers organic store discovery, which
      // cannot be split reliably into search versus recommendations here.
      if (method == 'play_referrer' &&
          params['utm_source'] == 'google-play' &&
          params['utm_medium'] == 'organic') {
        channel = 'google_play_organic';
        resolvedMethod = 'play_organic';
      }
      if (channel.isEmpty ||
          (channel == 'google_play_organic' &&
              resolvedMethod != 'play_organic')) {
        return {};
      }
      return sanitize({
        'marketingSource': channel,
        'marketingCampaign':
            params['utm_campaign'] ??
            (ref != null && ref.length > 1 ? ref.skip(1).join('_') : ''),
        'marketingMedium': params['utm_medium'],
        'marketingContent': params['utm_content'],
        'landingPage': params['landing_page'],
        'referrerHost': params['referrer_host'],
        'attributionMethod': resolvedMethod,
      });
    } on FormatException {
      return {};
    } on ArgumentError {
      return {};
    }
  }

  static String referrerSource(String rawHost) {
    final value = host(rawHost);
    bool isHost(String domain) => value == domain || value.endsWith('.$domain');
    // OAuth hosts describe authentication, not acquisition.
    if (value == 'accounts.google.com' ||
        value == 'oauth.yandex.ru' ||
        value == 'appleid.apple.com' ||
        value == 'id.yandex.ru') {
      return '';
    }
    for (final entry in const {
      'chatgpt.com': 'chatgpt',
      'chat.openai.com': 'chatgpt',
      'perplexity.ai': 'perplexity',
      'copilot.microsoft.com': 'copilot',
      'gemini.google.com': 'gemini',
      'claude.ai': 'claude',
      'threads.net': 'threads',
      'threads.com': 'threads',
      'instagram.com': 'instagram',
      'youtube.com': 'youtube',
      'youtu.be': 'youtube',
      'tiktok.com': 'tiktok',
      't.me': 'telegram',
      'telegram.org': 'telegram',
      'vk.com': 'vk',
      'vk.ru': 'vk',
      'bing.com': 'bing',
      'duckduckgo.com': 'duckduckgo',
      'ya.ru': 'yandex',
    }.entries) {
      if (isHost(entry.key)) return entry.value;
    }
    if (RegExp(
      r'^(?:[a-z0-9-]+\.)?yandex\.(?:ru|com|by|kz|uz|com\.tr)$',
    ).hasMatch(value)) {
      return 'yandex';
    }
    if (RegExp(
      r'^(?:[a-z0-9-]+\.)?google\.(?:com|ru|by|kz|co\.uk|de|fr|com\.au|co\.in|com\.tr|co\.jp|co\.kr|com\.br|com\.mx|ca|es|it|nl|pl|ua|uz|az|ge|am|ee|lt|lv|fi|se|no|dk|ch|at|be|cz|sk|ro|hu|pt|gr)$',
    ).hasMatch(value)) {
      return 'google';
    }
    return value.isEmpty ? '' : 'other';
  }

  static Map<String, String> fromBrowser(Uri uri, String referrer) {
    final tagged = fromQuery(uri.query, 'web_utm');
    final referrerUri = Uri.tryParse(referrer);
    final referrerHost = host(referrerUri?.host);
    final internal =
        referrerHost == uri.host ||
        const {'pdd-drive.ru', 'app.pdd-drive.ru'}.contains(referrerHost);
    final detected = internal ? '' : referrerSource(referrerHost);
    final channel =
        tagged['marketingSource'] ?? (detected.isEmpty ? 'direct' : detected);
    final medium = channel == 'direct'
        ? 'direct'
        : tagged.isNotEmpty
        ? 'referral'
        : const {'google', 'yandex', 'bing', 'duckduckgo'}.contains(channel)
        ? 'organic'
        : const {
            'chatgpt',
            'perplexity',
            'copilot',
            'gemini',
            'claude',
          }.contains(channel)
        ? 'ai'
        : 'referral';
    return {
      ...tagged,
      'marketingSource': channel,
      'attributionMethod': tagged['attributionMethod'] ?? 'web_referrer',
      'marketingMedium': tagged['marketingMedium'] ?? medium,
      if (tagged['landingPage'] == null && path(uri.path).isNotEmpty)
        'landingPage': path(uri.path),
      if (tagged['referrerHost'] == null && !internal && detected.isNotEmpty)
        'referrerHost': referrerHost,
    };
  }
}
