import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdd_app/core/config/backend_config.dart';
import 'package:pdd_app/data/services/network_retry.dart';
import 'package:pdd_app/data/services/notifier_api.dart';

void main() {
  setUp(NotifierRoute.reset);
  test(
    'idempotent status and payment check recover via fallback; creation does not replay',
    () async {
      final requests = <http.Request>[];
      await http.runWithClient(
        () async {
          expect((await NotifierApi.get('/api/user/status')).statusCode, 200);
          expect(
            requests.map((r) => r.url.host),
            BackendConfig.notifierHosts.map((h) => Uri.parse(h).host),
          );
          requests.clear();
          await NotifierApi.post(
            '/api/user/pay-intent',
            idempotent: false,
            body: 'order',
          );
          expect(requests, hasLength(1));
          expect(
            requests.single.url.host,
            Uri.parse(BackendConfig.notifierHosts.last).host,
          );
          NotifierRoute.reset();
          requests.clear();
          await NotifierApi.post(
            '/api/user/pay-check',
            idempotent: true,
            body: 'same-order',
          );
          expect(requests, hasLength(2));
          expect(requests.every((r) => r.body == 'same-order'), isTrue);
        },
        () => MockClient((request) async {
          requests.add(request);
          if (request.url.host == Uri.parse(BackendConfig.notifierUrl).host) {
            throw http.ClientException('blocked');
          }
          return http.Response('{}', 200);
        }),
      );
    },
  );
  test(
    'a one-shot request moves to the other address only when the first was never reached',
    () async {
      final primary = Uri.parse(BackendConfig.notifierUrl).host;
      for (final (error, expectedHosts) in <(Object, int)>[
        (const SocketException('Failed host lookup: \'blocked\''), 2),
        (const HandshakeException('Connection terminated during handshake'), 2),
        (
          const SocketException(
            'Connection refused',
            osError: OSError('Connection refused', 111),
          ),
          2,
        ),
        // The server may already have acted: never send the operation twice.
        (TimeoutException('no answer'), 1),
        (
          const SocketException(
            'Connection reset by peer',
            osError: OSError('Connection reset by peer', 104),
          ),
          1,
        ),
        (const HttpException('Connection closed before full header'), 1),
      ]) {
        NotifierRoute.reset();
        final hosts = <String>[];
        Future<http.Response> send() => http.runWithClient(
          () => NotifierApi.post(
            '/api/user/pay-intent',
            idempotent: false,
            body: 'order',
          ),
          () => MockClient((request) async {
            hosts.add(request.url.host);
            if (request.url.host == primary) throw error;
            return http.Response('{}', 200);
          }),
        );
        if (expectedHosts == 2) {
          expect((await send()).statusCode, 200, reason: '$error');
          expect(hosts, [
            primary,
            Uri.parse(BackendConfig.notifierHosts.last).host,
          ]);
          // The address that worked is used first from now on.
          expect(
            NotifierApi.uri('/x').host,
            Uri.parse(BackendConfig.notifierHosts.last).host,
          );
        } else {
          await expectLater(send(), throwsA(same(error)), reason: '$error');
          expect(hosts, [primary]);
        }
      }
    },
  );

  test('unknown creation outcome sends exactly one request', () async {
    var calls = 0;
    await http.runWithClient(
      () async {
        await expectLater(
          NotifierApi.post(
            '/api/user/pay-intent',
            idempotent: false,
            body: 'one',
          ),
          throwsA(isA<http.ClientException>()),
        );
        expect(calls, 1);
      },
      () => MockClient((_) async {
        calls++;
        throw http.ClientException('unknown outcome');
      }),
    );
  });
}
