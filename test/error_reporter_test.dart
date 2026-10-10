import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdd_app/data/services/error_reporter.dart';
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
    },
  );

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
}
