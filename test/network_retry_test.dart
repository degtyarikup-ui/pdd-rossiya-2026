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
  }) => sendWithRetry(
    send,
    hosts: hostList,
    attempts: short,
    pause: Duration.zero,
    stats: stats,
    stillWanted: stillWanted,
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
