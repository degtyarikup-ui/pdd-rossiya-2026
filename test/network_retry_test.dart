import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pdd_app/data/services/network_retry.dart';

void main() {
  const short = [
    Duration(milliseconds: 50),
    Duration(milliseconds: 50),
    Duration(milliseconds: 50),
  ];

  test('повисший первый запрос — вторая попытка проходит', () async {
    var calls = 0;
    final response = await sendWithRetry(
      () {
        calls++;
        if (calls == 1) return Completer<http.Response>().future; // завис
        return Future.value(http.Response('ok', 200));
      },
      attempts: short,
      pause: Duration.zero,
    );
    expect(response.statusCode, 200);
    expect(calls, 2);
  });

  test('сетевая ошибка повторяется', () async {
    var calls = 0;
    final response = await sendWithRetry(
      () async {
        calls++;
        if (calls < 3) throw http.ClientException('connection reset');
        return http.Response('ok', 200);
      },
      attempts: short,
      pause: Duration.zero,
    );
    expect(response.statusCode, 200);
    expect(calls, 3);
  });

  test('ответ сервера не повторяется, даже ошибка', () async {
    var calls = 0;
    final response = await sendWithRetry(
      () async {
        calls++;
        return http.Response('no', 401);
      },
      attempts: short,
      pause: Duration.zero,
    );
    expect(response.statusCode, 401);
    expect(calls, 1);
  });

  test('все попытки исчерпаны — таймаут, как раньше', () async {
    var calls = 0;
    await expectLater(
      sendWithRetry(
        () {
          calls++;
          return Completer<http.Response>().future;
        },
        attempts: short,
        pause: Duration.zero,
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(calls, 3);
  });

  test('сменился аккаунт — повтор не делается', () async {
    var calls = 0;
    await expectLater(
      sendWithRetry(
        () {
          calls++;
          return Completer<http.Response>().future;
        },
        attempts: short,
        pause: Duration.zero,
        stillWanted: () => false,
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(calls, 1);
  });
}
