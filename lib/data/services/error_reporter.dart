import 'package:pdd_app/data/services/diagnostic_context.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdd_app/data/services/network_retry.dart';
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/core/config/store_config.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/install_reporter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

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
    // Код Apple (failed, unknown, notHandled…) отличает сбой Apple ID на
    // устройстве от ответа в неожиданном формате; текст ошибки не пишем.
    if (error is SignInWithAppleAuthorizationException) {
      return 'apple_${error.code.name}';
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
      // Общие сбои канала плагина покупок: без них в отчёте остаётся sdk_error
      // и не видно, что именно не ответило магазину.
      'channel-error',
      'null-error',
      'error',
    };
    if (known.contains(code)) return code!;
    // Коды плагина покупок (storekit_…, storekit2_…): технические метки без
    // текста ошибки, строго по шаблону — по ним видно, что именно не прошло.
    if (code != null &&
        RegExp(r'^storekit2?_[a-z0-9_]{1,50}$').hasMatch(code)) {
      return code;
    }
    return 'sdk_error';
  }

  static void report(
    ErrorCategory category,
    String operation, {
    String? code,
    Object? error,
    String? provider,
    Map<String, dynamic>? context,
    StackTrace? stack,
  }) => unawaited(
    instance.record(
      category,
      operation,
      code: code ?? (error == null ? 'operation_failed' : codeFor(error)),
      provider: provider,
      context: {
        ...?context,
        if (stack != null) 'frames': DiagnosticContext.frames(stack),
      },
    ),
  );

  Future<void> record(
    ErrorCategory category,
    String operation, {
    required String code,
    String? provider,
    Map<String, dynamic>? context,
  }) {
    final details = DiagnosticContext.sanitize(context);
    final now = DateTime.now();
    final key =
        '${category.name}|$operation|$code|$provider|${details['phase']}|${details['stage']}|${details['sdkCodeHash']}|${(details['frames'] as List?)?.firstOrNull}';
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
      if (details.isNotEmpty) 'context': details,
    });
  }

  Future<void> flush() => _serialize(null);

  /// Адреса воркера. Запасной нужен только для боевого адреса; при другом
  /// `endpoint` (тесты, отдельная сборка) отправка идёт только на него.
  List<String> get _hosts => endpoint == BackendConfig.notifierUrl
      ? BackendConfig.notifierHosts
      : [endpoint];

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
        for (final e in events) {
          for (final pair in {
            'appVersion': 'version',
            'device': 'device',
            'os': 'os',
          }.entries) {
            if (!e.containsKey(pair.key) && metadata[pair.value] is String) {
              e[pair.key] = (metadata[pair.value] as String).substring(
                0,
                min(
                  pair.key == 'appVersion' ? 32 : 100,
                  (metadata[pair.value] as String).length,
                ),
              );
            }
          }
        }
        await prefs.setString(queueKey, jsonEncode(events));
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
                  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
                    'store': 'appStore',
                },
              )
              .toList();
          // Rich contexts must still fit the server's 16 KiB request limit.
          while (batch.length > 1 &&
              utf8
                      .encode(
                        jsonEncode({'installId': installId, 'events': batch}),
                      )
                      .length >
                  14000) {
            batch.removeLast();
          }
          // Отчёты идут туда же, куда и вход: если основной адрес недоступен,
          // пробуем запасной — иначе о таких сбоях мы бы не узнали никогда.
          http.Response? response;
          final hosts = _hosts;
          final start = NotifierRoute.preferredIndex(hosts);
          for (var i = 0; i < hosts.length && response == null; i++) {
            final host = hosts[(start + i) % hosts.length];
            try {
              response = await _client
                  .post(
                    Uri.parse(
                      host,
                    ).replace(path: '/api/diagnostics', query: ''),
                    headers: {
                      ..._headers(),
                      'content-type': 'application/json',
                      'x-install-secret': secret,
                    },
                    body: jsonEncode({'installId': installId, 'events': batch}),
                  )
                  .timeout(const Duration(seconds: 10));
              NotifierRoute.remember(host);
            } catch (_) {
              // Следующий адрес; если он последний — отчёт останется в очереди.
            }
          }
          if (response == null || response.statusCode != 200) return;
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
