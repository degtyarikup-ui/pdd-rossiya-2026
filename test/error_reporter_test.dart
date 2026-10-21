import 'package:flutter/foundation.dart';
import 'package:pdd_app/data/services/diagnostic_context.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/data/services/error_reporter.dart';
import 'package:pdd_app/data/services/network_retry.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'offline errors retry original IDs after restart and omit raw secrets',
    () async {
      var online = false;
      final requests = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        expect(request.url.path, '/api/diagnostics');
        expect(request.headers['x-install-secret'], 'test');
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        expect(request.body, isNot(contains('TOP_SECRET')));
        return http.Response('{}', online ? 200 : 503);
      });
      ErrorReporter create() => ErrorReporter(
        endpoint: 'https://test',
        secret: 'test',
        client: client,
        metadata: () async => {
          'version': '2.2.0+50',
          'device': 'Phone',
          'credential': 'TOP_SECRET',
        },
        headers: () => {},
        userId: () => 'google_test',
      );
      final reporter = create();
      await reporter.record(
        ErrorCategory.auth,
        'auth.provider',
        code: ErrorReporter.codeFor(http.ClientException('TOP_SECRET')),
      );
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString(ErrorReporter.queueKey)!);
      expect(saved, hasLength(1));
      expect(saved[0]['code'], 'network');
      online = true;
      await create().flush();
      expect(requests.last['events'][0]['id'], saved[0]['id']);
      expect(requests.last['events'][0]['ts'], saved[0]['ts']);
      expect(jsonDecode(prefs.getString(ErrorReporter.queueKey)!), isEmpty);
    },
  );

  test(
    'отчёт уходит через запасной адрес, если основной не отвечает',
    () async {
      final hosts = <String>[];
      final client = MockClient((request) async {
        hosts.add(request.url.host);
        // Основной адрес (workers.dev) недоступен, запасной работает.
        if (request.url.host.endsWith('workers.dev')) {
          throw http.ClientException('no route');
        }
        return http.Response('{}', 200);
      });
      NotifierRoute.reset();
      final reporter = ErrorReporter(
        endpoint: BackendConfig.notifierUrl,
        secret: 'test',
        client: client,
        metadata: () async => {},
        headers: () => {},
        userId: () => null,
      );
      await reporter.record(
        ErrorCategory.auth,
        'auth.provider',
        code: 'timeout:3x',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString(ErrorReporter.queueKey)!), isEmpty);
      expect(hosts.first, endsWith('workers.dev'));
      expect(hosts.last, 'api.pdd-drive.app');
    },
  );

  test(
    'same error is locally throttled; a different operation remains visible',
    () async {
      var sent = 0;
      final reporter = ErrorReporter(
        endpoint: 'https://test',
        secret: 'test',
        metadata: () async => {},
        headers: () => {},
        userId: () => null,
        client: MockClient((_) async {
          sent++;
          return http.Response('{}', 200);
        }),
      );
      await reporter.record(
        ErrorCategory.purchase,
        'iap.buy',
        code: 'store_unavailable',
      );
      await reporter.record(
        ErrorCategory.purchase,
        'iap.buy',
        code: 'store_unavailable',
      );
      await reporter.record(
        ErrorCategory.purchase,
        'iap.verify',
        code: 'network',
      );
      expect(sent, 2);
    },
  );

  test(
    'outbox is bounded, skips expired events and works when metadata fails',
    () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({
        ErrorReporter.queueKey: jsonEncode(
          List.generate(
            65,
            (i) => {
              'id': i.toRadixString(16).padLeft(32, '0'),
              'ts': i == 0 ? 0 : now,
              'category': 'app',
              'operation': 'flutter.framework',
              'code': 'exception',
            },
          ),
        ),
      });
      final batches = <int>[];
      final reporter = ErrorReporter(
        endpoint: 'https://test',
        secret: 'test',
        metadata: () async => throw StateError('plugin unavailable'),
        headers: () => {},
        userId: () => null,
        client: MockClient((request) async {
          batches.add((jsonDecode(request.body)['events'] as List).length);
          return http.Response('{}', 200);
        }),
      );
      await reporter.flush();
      expect(batches, [10, 10, 10, 10, 10]);
    },
  );

  test(
    'diagnostics fail closed without a key; classification excludes messages',
    () async {
      final reporter = ErrorReporter(
        endpoint: 'https://test',
        secret: '',
        client: MockClient((_) async => throw StateError('must not send')),
      );
      await reporter.record(
        ErrorCategory.app,
        'startup.progress',
        code: 'exception',
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          ErrorReporter.queueKey,
        ),
        isNull,
      );
      expect(ErrorReporter.codeFor(TimeoutException('TOP_SECRET')), 'timeout');
      expect(
        ErrorReporter.codeFor(
          PlatformException(code: 'TOP_SECRET', message: 'TOP_SECRET'),
        ),
        'sdk_error',
      );
      expect(
        ErrorReporter.codeFor(StateError('TOP_SECRET')),
        'exception_StateError',
      );
      expect(
        ErrorReporter.codeFor(
          const SignInWithAppleAuthorizationException(
            code: AuthorizationErrorCode.unknown,
            message: 'TOP_SECRET',
          ),
        ),
        'apple_unknown',
      );
    },
  );

  test('коды StoreKit проходят в отчёт, остальное и чужие тексты — нет', () {
    expect(
      ErrorReporter.sdkCode('storekit_getproductrequest_platform_exception'),
      'storekit_getproductrequest_platform_exception',
    );
    expect(
      ErrorReporter.sdkCode('storekit2_failed_to_fetch_product'),
      'storekit2_failed_to_fetch_product',
    );
    expect(ErrorReporter.sdkCode('storekit_error'), 'storekit_error');
    // Общие коды канала плагина покупок — иначе не видно, что не ответило.
    expect(ErrorReporter.sdkCode('channel-error'), 'channel-error');
    expect(ErrorReporter.sdkCode('null-error'), 'null-error');
    expect(ErrorReporter.sdkCode('user@example.com'), 'sdk_error');
    expect(ErrorReporter.sdkCode('storekit_Account user@x.com'), 'sdk_error');
    expect(ErrorReporter.sdkCode(null), 'sdk_error');
  });

  test('Google sign-in keeps the ApiException number but never its text', () {
    expect(
      ErrorReporter.codeFor(
        PlatformException(
          code: 'sign_in_failed',
          message:
              'com.google.android.gms.common.api.ApiException: 10: account user@example.com',
        ),
      ),
      'sign_in_failed:10',
    );
    expect(
      ErrorReporter.codeFor(
        PlatformException(code: 'sign_in_failed', message: 'boom'),
      ),
      'sign_in_failed',
    );
    expect(
      ErrorReporter.codeFor(
        PlatformException(
          code: 'sign_in_canceled',
          message: 'ApiException: 12501',
        ),
      ),
      'sdk_error',
    );
  });
  test(
    'context preserves safe stages and app frames, strips raw diagnostic data',
    () {
      final frames = DiagnosticContext.frames(
        StackTrace.fromString(
          '#0 callback (package:pdd_app/screens/home.dart:12:8)\n'
          '#1 secret (https://host.test/user?token=TOP_SECRET)\n'
          '#2 native (/Users/private/user.dart:12:8)',
        ),
      );
      expect(frames, ['package:pdd_app/screens/home.dart:12:8']);
      final context = DiagnosticContext.sanitize({
        'phase': 'paywall',
        'stage': 'query',
        'attempt': 3,
        'requestedCount': 27,
        'returnedCount': 0,
        'missingIds': ['ru.pdd.pddapp.sub.week', 'user@example.com'],
        'sdkCodeHash': '0123456789abcdef',
        'message': 'TOP_SECRET',
        'frames': [...frames, 'https://host.test/TOP_SECRET'],
      });
      expect(context['phase'], 'paywall');
      expect(context['frames'], frames);
      expect(context['missingIds'], ['ru.pdd.pddapp.sub.week']);
      expect(jsonEncode(context), isNot(contains('TOP_SECRET')));
      expect(jsonEncode(context), isNot(contains('user@example.com')));
    },
  );

  test(
    'foreground failure is not suppressed by background prefetch and offline metadata keeps original version',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var version = '2.2.4+65';
      var online = false;
      final sent = <Map>[];
      final reporter = ErrorReporter(
        endpoint: 'https://test',
        secret: 'test',
        metadata: () async => {
          'version': version,
          'os': 'iOS 26.5',
          'device': 'iPhone',
        },
        headers: () => {},
        userId: () => null,
        client: MockClient((request) async {
          sent.add(jsonDecode(request.body));
          return http.Response('{}', online ? 200 : 503);
        }),
      );
      await reporter.record(
        ErrorCategory.purchase,
        'iap.products',
        code: 'sdk_error',
        context: {'phase': 'background', 'stage': 'query'},
      );
      version = '2.2.5+66';
      await reporter.record(
        ErrorCategory.purchase,
        'iap.products',
        code: 'sdk_error',
        context: {'phase': 'paywall', 'stage': 'query'},
      );
      online = true;
      await reporter.flush();
      final events = sent.last['events'] as List;
      expect(events, hasLength(2));
      expect(events[0]['context']['phase'], 'background');
      expect(events[0]['appVersion'], '2.2.4+65');
      expect(events[1]['appVersion'], '2.2.5+66');
      expect(events[0]['os'], 'iOS 26.5');
      expect(events[0]['store'], 'appStore');
    },
  );
  test('rich outbox batches stay below the server byte limit', () async {
    final longName = 'a' * 100;
    final context = DiagnosticContext.sanitize({
      'phase': 'paywall',
      'stage': 'query',
      'attempt': 3,
      'requestedCount': 27,
      'missingIds': DiagnosticContext.productIds.toList(),
      'frames': List.generate(
        6,
        (i) => 'package:pdd_app/services/$longName$i.dart:12345:123',
      ),
    });
    final now = DateTime.now().millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      ErrorReporter.queueKey: jsonEncode(
        List.generate(
          10,
          (i) => {
            'id': i.toRadixString(16).padLeft(32, '0'),
            'ts': now,
            'category': 'app',
            'operation': 'flutter.framework',
            'code': 'exception_StateError',
            'context': context,
          },
        ),
      ),
    });
    var requests = 0, events = 0;
    final reporter = ErrorReporter(
      endpoint: 'https://test',
      secret: 'test',
      metadata: () async => {'device': 'Ж' * 100, 'version': '2.2.4+65'},
      headers: () => {},
      userId: () => null,
      client: MockClient((request) async {
        requests++;
        expect(utf8.encode(request.body).length, lessThanOrEqualTo(14000));
        events += (jsonDecode(request.body)['events'] as List).length;
        return http.Response('{}', 200);
      }),
    );
    await reporter.flush();
    expect(events, 10);
    expect(requests, greaterThan(1));
  });
}
