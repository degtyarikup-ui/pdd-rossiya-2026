import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdd_app/core/config/store_config.dart';
import 'package:pdd_app/data/services/acquisition_fields.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdd_app/data/services/browser_info_stub.dart'
    if (dart.library.js_interop) 'package:pdd_app/data/services/browser_info_web.dart';

class AcquisitionService {
  static const _key = 'acquisition_v1';
  static Future<Map<String, String>>? _pending;

  static Map<String, String> parseReferrer(String raw, String method) =>
      AcquisitionFields.fromQuery(raw, method);

  static Future<Map<String, String>> fields() => _pending ??= _read();

  static Future<Map<String, String>> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (saved != null) {
        try {
          final decoded = jsonDecode(saved);
          if (decoded is Map) {
            final first = AcquisitionFields.sanitize(decoded);
            if (first.isNotEmpty) return first;
          }
        } on FormatException {
          // A broken old preference must not discard the current referral.
        }
      }
      Map<String, String> result = {};
      if (kIsWeb) {
        result = browserAcquisitionFields();
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        final rustore = StoreConfig.current == AppStore.rustore;
        final raw = await const MethodChannel('pdd/acquisition')
            .invokeMethod<String>(
              rustore ? 'rustoreInstallReferrer' : 'installReferrer',
            )
            .timeout(const Duration(seconds: 4));
        if (raw != null) {
          result = parseReferrer(
            raw,
            rustore ? 'rustore_referrer' : 'play_referrer',
          );
        }
      }
      if (result.isNotEmpty) await prefs.setString(_key, jsonEncode(result));
      return result;
    } catch (_) {
      if (kIsWeb) {
        try {
          // The direct browser bridge also works when the preferences plugin
          // cannot register or its own storage is unavailable.
          return browserAcquisitionFields();
        } catch (_) {}
      }
      return {}; // Attribution never blocks login or changes its outcome.
    }
  }

  @visibleForTesting
  static void resetForTesting() => _pending = null;
}
