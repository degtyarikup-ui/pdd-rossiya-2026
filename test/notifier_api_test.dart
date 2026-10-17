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
