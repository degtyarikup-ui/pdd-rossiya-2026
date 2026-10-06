import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdd_app/data/services/browser_info_stub.dart'
    if (dart.library.js_interop) 'package:pdd_app/data/services/browser_info_web.dart';

class AcquisitionService {
  static const _key = 'acquisition_v1';
  static Future<Map<String, String>>? _pending;

  static Map<String, String> parseReferrer(String raw, String method) {
    final params = Uri.splitQueryString(raw);
    final ref = params['ref']?.split('_');
    var source = (params['utm_source'] ?? ref?.first ?? '').toLowerCase();
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
        params['utm_campaign'] ??
        (ref != null && ref.length > 1 ? ref.skip(1).join('_') : '');
    return {
      'marketingSource': source,
      if (RegExp(r'^[A-Za-z0-9._-]{1,64}$').hasMatch(campaign))
        'marketingCampaign': campaign,
      'attributionMethod': method,
    };
  }

  static Future<Map<String, String>> fields() => _pending ??= _read();

  static Future<Map<String, String>> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (saved != null) {
        return Map<String, String>.from(jsonDecode(saved) as Map);
      }
      Map<String, String> result = {};
      if (kIsWeb) {
        result = browserAcquisitionFields();
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        final raw = await const MethodChannel('pdd/acquisition')
            .invokeMethod<String>('installReferrer')
            .timeout(const Duration(seconds: 4));
        if (raw != null) result = parseReferrer(raw, 'play_referrer');
      }
      if (result.isNotEmpty) await prefs.setString(_key, jsonEncode(result));
      return result;
    } catch (_) {
      return {}; // Attribution never blocks login or changes its outcome.
    }
  }
}
