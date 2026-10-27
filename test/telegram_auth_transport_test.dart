import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdd_app/data/services/network_retry.dart';
import 'package:pdd_app/data/services/telegram_auth_transport.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/telegram_auth_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

const hosts = ['https://primary.invalid', 'https://fallback.invalid'];
const healthBody = '{"ok":true,"available":false,"methods":["sbp"]}';
http.Response challenge([String nonce = 'auth_test']) => http.Response(
  jsonEncode({
    'ok': true,
    'nonce': nonce,
    'botUsername': 'test_bot',
    'botUrl': 'https://t.me/test_bot?start=$nonce',
    'tgUrl': 'tg://resolve?domain=test_bot&start=$nonce',
  }),
  200,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    NotifierRoute.reset();
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'primary probe fails, one fallback challenge POST succeeds, every check stays on that host',
    () async {
      final calls = <http.Request>[];
      final transport = TelegramAuthTransport(
        hosts: hosts,
        client: MockClient((request) async {
          calls.add(request);
          if (request.method == 'GET') {
            expect(request.headers.containsKey('x-install-secret'), false);
            expect(request.followRedirects, false);
            if (request.url.host == 'primary.invalid') {
              throw http.ClientException('offline');
            }
            return http.Response(healthBody, 200);
          }
          expect(request.url.host, 'fallback.invalid');
          return request.url.path.endsWith('/request')
              ? challenge()
              : http.Response('{"ok":false,"status":"pending"}', 200);
        }),
      );
      final accepted = await transport.createChallenge(stillWanted: () => true);
      expect(accepted.host, hosts[1]);
      await transport.check(accepted);
      expect(calls.map((r) => '${r.method} ${r.url.host} ${r.url.path}'), [
        'GET primary.invalid /api/pay/status',
        'GET fallback.invalid /api/pay/status',
        'POST fallback.invalid /api/auth/telegram/request',
        'POST fallback.invalid /api/auth/telegram/check',
      ]);
      transport.close();
    },
  );

  test(
    'uncertain challenge POST is never replayed on primary or fallback',
    () async {
      var probes = 0, writes = 0;
      final transport = TelegramAuthTransport(
        hosts: hosts,
        client: MockClient((request) async {
          if (request.method == 'GET') {
            probes++;
            return http.Response(healthBody, 200);
          }
          writes++;
          throw http.ClientException('response lost');
        }),
      );
      await expectLater(
        transport.createChallenge(stillWanted: () => true),
        throwsA(isA<http.ClientException>()),
      );
      expect(probes, 1);
      expect(writes, 1);
      transport.close();
    },
  );

  test(
    'Telegram route selection accepts payments enabled or disabled without depending on methods',
    () async {
      for (final available in [false, true]) {
        final transport = TelegramAuthTransport(
          hosts: hosts,
          client: MockClient(
            (request) async => request.method == 'GET'
                ? http.Response(
                    jsonEncode({'ok': true, 'available': available}),
                    200,
                  )
                : challenge(),
          ),
        );
        expect(
          (await transport.createChallenge(stillWanted: () => true)).host,
          hosts.first,
        );
        transport.close();
      }
    },
  );

  test(
    'a hung GET probe has a deadline and can select fallback without repeating a POST',
    () async {
      final hung = Completer<http.Response>();
      var writes = 0;
      final transport = TelegramAuthTransport(
        hosts: hosts,
        probeTimeout: const Duration(milliseconds: 15),
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return request.url.host == 'primary.invalid'
                ? hung.future
                : http.Response(healthBody, 200);
          }
          writes++;
          return challenge();
        }),
      );
      expect(
        (await transport.createChallenge(stillWanted: () => true)).host,
        hosts[1],
      );
      expect(writes, 1);
      hung.complete(http.Response(healthBody, 200));
      transport.close();
    },
  );

  test(
    'disposing during route selection prevents challenge creation',
    () async {
      final pending = Completer<http.Response>();
      var wanted = true, writes = 0;
      final transport = TelegramAuthTransport(
        hosts: hosts,
        client: MockClient((request) async {
          if (request.method == 'GET') return pending.future;
          writes++;
          return challenge();
        }),
      );
      final result = transport.createChallenge(stillWanted: () => wanted);
      wanted = false;
      pending.complete(http.Response(healthBody, 200));
      await expectLater(result, throwsA(isA<TelegramAuthCancelled>()));
      expect(writes, 0);
      transport.close();
    },
  );

  Future<void> open(
    WidgetTester tester,
    TelegramAuthTransport transport,
    Future<void> Function() launch,
  ) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: TelegramAuthSheet(transport: transport, openTelegram: launch),
      ),
    ),
  );

  testWidgets(
    'an uncertain check stops polling and offers an explicit retry with a new challenge',
    (tester) async {
      var requests = 0, checks = 0, launches = 0;
      final transport = TelegramAuthTransport(
        hosts: hosts,
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(healthBody, 200);
          }
          if (request.url.path.endsWith('/request')) {
            requests++;
            return challenge('auth_test_$requests');
          }
          checks++;
          throw http.ClientException('check response lost');
        }),
      );
      await open(tester, transport, () async {
        launches++;
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump();
      expect(requests, 1);
      expect(checks, 1);
      expect(launches, 1);
      expect(find.text(appL10n.authErrorNetwork), findsOneWidget);
      expect(find.text(appL10n.supportChatRetry), findsOneWidget);
      await tester.pump(const Duration(seconds: 15));
      expect(checks, 1);
      await tester.tap(find.text(appL10n.supportChatRetry));
      await tester.pump();
      expect(requests, 2);
      expect(launches, 2);
      expect(checks, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'disposed sheet ignores a late challenge and cannot open Telegram or start polls',
    (tester) async {
      final pending = Completer<http.Response>();
      var probes = 0, writes = 0, launches = 0;
      final transport = TelegramAuthTransport(
        hosts: hosts,
        client: MockClient((request) async {
          if (request.method == 'GET') {
            probes++;
            return http.Response(healthBody, 200);
          }
          writes++;
          return pending.future;
        }),
      );
      await open(tester, transport, () async {
        launches++;
      });
      await tester.pump();
      expect(probes, 1);
      expect(writes, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(challenge());
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      expect(launches, 0);
      expect(writes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'paused or inactive app does not poll; resume checks once on the accepted route',
    (tester) async {
      var checks = 0;
      final transport = TelegramAuthTransport(
        hosts: hosts,
        client: MockClient((request) async {
          if (request.method == 'GET') return http.Response(healthBody, 200);
          if (request.url.path.endsWith('/request')) return challenge();
          checks++;
          expect(request.url.host, 'primary.invalid');
          return http.Response('{"ok":false,"status":"pending"}', 200);
        }),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await open(tester, transport, () async {});
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(seconds: 6));
      expect(checks, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 6));
      expect(checks, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(checks, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('disposed sheet cannot accept a late one-time claim response', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    var checks = 0;
    final transport = TelegramAuthTransport(
      hosts: hosts,
      client: MockClient((request) async {
        if (request.method == 'GET') return http.Response(healthBody, 200);
        if (request.url.path.endsWith('/request')) return challenge();
        checks++;
        return pending.future;
      }),
    );
    await open(tester, transport, () async {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump();
    expect(checks, 1);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Current route'))),
    );
    pending.complete(
      http.Response(
        jsonEncode({
          'ok': true,
          'status': 'confirmed',
          'token': 'test-session',
          'expiresAt': DateTime.now()
              .add(const Duration(days: 1))
              .toIso8601String(),
          'user': {
            'id': 'telegram_test',
            'provider': 'telegram',
            'name': 'Test',
            'createdAt': DateTime(2026).toIso8601String(),
          },
        }),
        200,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(checks, 1);
    expect(find.text('Current route'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
