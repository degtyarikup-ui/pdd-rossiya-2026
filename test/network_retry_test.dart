import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/data/services/network_retry.dart';

void main() {
  const short = [
    Duration(milliseconds: 50),
    Duration(milliseconds: 50),
    Duration(milliseconds: 50),
  ];
  const hosts = ['https://main', 'https://backup'];

  setUp(NotifierRoute.reset);

  Future<http.Response> run(
    Future<http.Response> Function(String host) send, {
    List<String> hostList = hosts,
    RetryStats? stats,
    bool Function()? stillWanted,
    Set<int> retryStatusCodes = const {},
    Duration pause = Duration.zero,
  }) => sendWithRetry(
    send,
    hosts: hostList,
    attempts: short,
    pause: pause,
    stats: stats,
    stillWanted: stillWanted,
    retryStatusCodes: retryStatusCodes,
  );

  test('повисший основной адрес — запрос проходит через запасной', () async {
    final tried = <String>[];
    final stats = RetryStats();
    final response = await run((host) {
      tried.add(host);
      if (host == 'https://main') return Completer<http.Response>().future;
      return Future.value(http.Response('ok', 200));
    }, stats: stats);
    expect(response.statusCode, 200);
    expect(tried, ['https://main', 'https://backup']);
    expect(stats.attempts, 2);
    expect(stats.host, 'https://backup');
    expect(stats.neededRecovery, isTrue);
  });

  test('адрес, который сработал, пробуется первым в следующий раз', () async {
    const pair = ['https://dead', 'https://alive'];
    await run((host) async {
      if (host == 'https://dead') throw http.ClientException('no route');
      return http.Response('ok', 200);
    }, hostList: pair);
    final tried = <String>[];
    await run((host) async {
      tried.add(host);
      return http.Response('ok', 200);
    }, hostList: pair);
    expect(tried, ['https://alive']);
  });

  test('сетевая ошибка повторяется', () async {
    var calls = 0;
    final response = await run((host) async {
      calls++;
      if (calls < 3) throw http.ClientException('connection reset');
      return http.Response('ok', 200);
    });
    expect(response.statusCode, 200);
    expect(calls, 3);
  });

  test('ответ сервера не повторяется, даже ошибка', () async {
    var calls = 0;
    final stats = RetryStats();
    final response = await run((host) async {
      calls++;
      return http.Response('no', 401);
    }, stats: stats);
    expect(response.statusCode, 401);
    expect(calls, 1);
    expect(stats.neededRecovery, isFalse);
  });

  test(
    'temporary statuses retry only with explicit idempotent opt-in',
    () async {
      var calls = 0;
      final original = await run((host) async {
        calls++;
        return http.Response('unavailable', 503);
      });
      expect(original.statusCode, 503);
      expect(calls, 1);
      calls = 0;
      final tried = <String>[];
      final stats = RetryStats();
      final recovered = await run(
        (host) async {
          tried.add(host);
          calls++;
          return http.Response('reply', calls == 1 ? 503 : 200);
        },
        retryStatusCodes: {503},
        stats: stats,
      );
      expect(recovered.statusCode, 200);
      expect(tried, hosts);
      expect(stats.attempts, 2);
      expect(stats.neededRecovery, isTrue);
      expect(NotifierRoute.preferredIndex(hosts), 1);
    },
  );

  test(
    'credential rejection never retries with transient statuses enabled',
    () async {
      var calls = 0;
      final response = await run((_) async {
        calls++;
        return http.Response('invalid credentials', 401);
      }, retryStatusCodes: {500, 502, 503, 504});
      expect(response.statusCode, 401);
      expect(calls, 1);
    },
  );

  test(
    'long Retry-After is returned without an early retry or unbounded wait',
    () async {
      for (final value in ['30', 'Thu, 22 Oct 2026 15:00:00 GMT']) {
        var calls = 0;
        final response = await run((_) async {
          calls++;
          return http.Response('busy', 503, headers: {'retry-after': value});
        }, retryStatusCodes: {503});
        expect(response.statusCode, 503);
        expect(calls, 1);
      }
    },
  );

  test(
    'retry exhaustion returns the last service response and does not prefer a failed route',
    () async {
      var calls = 0;
      final stats = RetryStats();
      final response = await run(
        (_) async {
          calls++;
          return http.Response('busy', 503);
        },
        retryStatusCodes: {503},
        stats: stats,
      );
      expect(response.statusCode, 503);
      expect(calls, short.length);
      expect(stats.attempts, short.length);
      expect(stats.host, isNull);
      expect(NotifierRoute.preferredIndex(hosts), 0);
    },
  );

  test('short Retry-After is honored before retrying a safe request', () async {
    var calls = 0;
    final elapsed = Stopwatch()..start();
    final response = await run((_) async {
      calls++;
      return calls == 1
          ? http.Response('busy', 503, headers: {'retry-after': '1'})
          : http.Response('ok', 200);
    }, retryStatusCodes: {503});
    expect(response.statusCode, 200);
    expect(calls, 2);
    expect(elapsed.elapsed, greaterThanOrEqualTo(const Duration(seconds: 1)));
  });

  test('account changing during backoff prevents the next request', () async {
    var wanted = true, calls = 0;
    await expectLater(
      run(
        (_) async {
          calls++;
          Timer(const Duration(milliseconds: 2), () => wanted = false);
          throw http.ClientException('reset');
        },
        stillWanted: () => wanted,
        pause: const Duration(milliseconds: 10),
      ),
      throwsA(isA<http.ClientException>()),
    );
    expect(calls, 1);
  });

  test('все попытки исчерпаны — таймаут, число попыток известно', () async {
    var calls = 0;
    final stats = RetryStats();
    await expectLater(
      run((host) {
        calls++;
        return Completer<http.Response>().future;
      }, stats: stats),
      throwsA(isA<TimeoutException>()),
    );
    expect(calls, 3);
    expect(stats.attempts, 3);
    expect(stats.host, isNull);
  });

  test('сменился аккаунт — повтор не делается', () async {
    var calls = 0;
    await expectLater(
      run((host) {
        calls++;
        return Completer<http.Response>().future;
      }, stillWanted: () => false),
      throwsA(isA<TimeoutException>()),
    );
    expect(calls, 1);
  });

  test('один адрес — повторы идут на него же', () async {
    final tried = <String>[];
    await expectLater(
      run((host) {
        tried.add(host);
        return Completer<http.Response>().future;
      }, hostList: ['https://main']),
      throwsA(isA<TimeoutException>()),
    );
    expect(tried, ['https://main', 'https://main', 'https://main']);
  });

  test('запасной адрес подключён только к боевому воркеру', () {
    final configured = BackendConfig.notifierHosts;
    expect(configured.first, BackendConfig.notifierUrl);
    expect(configured, contains('https://api.pdd-drive.app'));
    expect(configured.toSet().length, configured.length);
  });
}
