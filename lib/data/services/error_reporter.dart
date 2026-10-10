import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/core/config/store_config.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/install_reporter.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ErrorCategory { auth, purchase, app }

/// Bounded diagnostic outbox. Only codes and technical metadata are saved;
/// exception messages, credentials, receipts and headers are never persisted.
class ErrorReporter {
  ErrorReporter({
    this.endpoint = BackendConfig.notifierUrl,
    this.secret = BackendConfig.notifierSecret,
    http.Client? client,
    Future<Map<String, dynamic>> Function()? metadata,
    Map<String, String> Function()? headers,
    String? Function()? userId,
  }) : _client = client ?? http.Client(),
       _metadata = metadata ?? InstallReporter.clientMetadata,
       _headers = headers ?? (() => AuthService.instance.serverHeaders),
       _userId = userId ?? (() => AuthService.instance.currentUser?.id);

  static final instance = ErrorReporter();
  static const queueKey = 'error_events_v1';
  final String endpoint;
  final String secret;
  final http.Client _client;
  final Future<Map<String, dynamic>> Function() _metadata;
  final Map<String, String> Function() _headers;
  final String? Function() _userId;
  final Map<String, DateTime> _last = {};
  Future<void> _tail = Future.value();

  static String codeFor(Object error) {
    if (error is TimeoutException) return 'timeout';
    if (error is http.ClientException) return 'network';
    if (error is FormatException || error is TypeError) {
      return 'invalid_response';
    }
    if (error is PlatformException) {
      final code = sdkCode(error.code);
      // google_sign_in сводит разные сбои в sign_in_failed. Номер ApiException
      // отличает их (10 — настройки OAuth-клиента, 12500 — сбой Google Play
      // Services). Сохраняем только цифры, текст ошибки не пишем.
      final api = RegExp(
        r'ApiException: (\d{1,5})',
      ).firstMatch(error.message ?? '');
      return code == 'sign_in_failed' && api != null
          ? '$code:${api.group(1)}'
          : code;
    }
    final type = 'exception_${error.runtimeType}'.replaceAll(
      RegExp('[^a-zA-Z0-9_]'),
      '',
    );
    return type.substring(0, min(80, type.length));
  }

  static String sdkCode(String? code) {
    const known = {
      'sign_in_failed',
      'network_error',
      'sign_in_required',
      'storekit_error',
      'purchase_error',
      'billing_unavailable',
      'service_unavailable',
      'item_unavailable',
      'developer_error',
      'storage_error',
    };
    return known.contains(code) ? code! : 'sdk_error';
  }

  static void report(
    ErrorCategory category,
    String operation, {
    String? code,
    Object? error,
    String? provider,
  }) => unawaited(
    instance.record(
      category,
      operation,
      code: code ?? (error == null ? 'operation_failed' : codeFor(error)),
      provider: provider,
    ),
  );

  Future<void> record(
    ErrorCategory category,
    String operation, {
    required String code,
    String? provider,
  }) {
    final now = DateTime.now();
    final key = '${category.name}|$operation|$code|$provider';
    if (now.difference(_last[key] ?? DateTime(2000)) <
        const Duration(minutes: 10)) {
      return flush();
    }
    _last[key] = now;
    if (_last.length > 200) _last.remove(_last.keys.first);
    final random = Random.secure();
    return _serialize({
      'id': List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
      'ts': now.millisecondsSinceEpoch,
      'category': category.name,
      'operation': operation,
      'code': code,
      'provider': ?provider,
      'userId': ?_userId(),
    });
  }

  Future<void> flush() => _serialize(null);

  Future<void> _serialize(Map<String, dynamic>? event) {
    _tail = _tail.then((_) async {
      if (!endpoint.startsWith('https://') || secret.isEmpty) return;
      try {
        final prefs = await SharedPreferences.getInstance();
        final now = DateTime.now().millisecondsSinceEpoch;
        final events = (jsonDecode(prefs.getString(queueKey) ?? '[]') as List)
            .cast<Map<String, dynamic>>()
            .where(
              (e) =>
                  e['ts'] is int &&
                  now - (e['ts'] as int) <
                      const Duration(days: 7).inMilliseconds,
            )
            .toList();
        if (event != null) {
          // Persist first: metadata plugins or the network may be unavailable.
          events.add(event);
        }
        if (events.length > 50) events.removeRange(0, events.length - 50);
        await prefs.setString(queueKey, jsonEncode(events));
        if (events.isEmpty) return;
        Map<String, dynamic> metadata = {};
        try {
          metadata = await _metadata().timeout(const Duration(seconds: 3));
        } catch (_) {}
        final installId = await InstallReporter.installationId();
        while (events.isNotEmpty) {
          final batch = events
              .take(10)
              .map(
                (e) => {
                  ...e,
                  'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
                  // Сборка RuStore и Google Play подписаны разными ключами и
                  // проходят вход Google по-разному: различаем их в отчёте.
                  if (!kIsWeb &&
                      defaultTargetPlatform == TargetPlatform.android)
                    'store': StoreConfig.current.name,
                  if (metadata['version'] is String)
                    'appVersion': (metadata['version'] as String).substring(
                      0,
                      min(32, (metadata['version'] as String).length),
                    ),
                  if (metadata['device'] is String)
                    'device': (metadata['device'] as String).substring(
                      0,
                      min(100, (metadata['device'] as String).length),
                    ),
                },
              )
              .toList();
          final response = await _client
              .post(
                Uri.parse(
                  endpoint,
                ).replace(path: '/api/diagnostics', query: ''),
                headers: {
                  ..._headers(),
                  'content-type': 'application/json',
                  'x-install-secret': secret,
                },
                body: jsonEncode({'installId': installId, 'events': batch}),
              )
              .timeout(const Duration(seconds: 10));
          if (response.statusCode != 200) return;
          events.removeRange(0, batch.length);
          await prefs.setString(queueKey, jsonEncode(events));
        }
      } catch (_) {
        // Do not report the reporter's own failures.
      }
    });
    return _tail;
  }
}
