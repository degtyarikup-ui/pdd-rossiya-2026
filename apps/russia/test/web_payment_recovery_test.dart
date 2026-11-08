import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/pending_payment.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/web_payment_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const order = '11111111-1111-4111-8111-111111111111';
  final auth = AuthService.instance, premium = PremiumService.instance;
  final expiry = DateTime.now().add(const Duration(days: 7));
  UserProfile user(String name) => UserProfile(
    id: 'google_$name',
    name: name,
    email: 'owner@example.invalid',
    provider: AuthProviderType.google,
    createdAt: DateTime(2026),
  );
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'auth_user_profile': user('A').toJson(),
    });
    FlutterSecureStorage.setMockInitialValues({
      'pdd_server_session': jsonEncode({
        'userId': 'google_A',
        'token': 'session',
        'expiresAt': expiry.toIso8601String(),
      }),
    });
    await http.runWithClient(
      () async {
        await premium.init();
        await auth.init();
      },
      () => MockClient(
        (_) async => http.Response('{"ok":true,"isPremium":false}', 200),
      ),
    );
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('pdd/device_region'),
          (_) async => 'RU',
        );
    updateAppLocale(const Locale('ru'));
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('pdd/device_region'),
          null,
        );
    updateAppLocale(const Locale('ru'));
  });
  test(
    '503 pending and 409 unknown preserve the order for its owner without two-hour expiry',
    () async {
      for (final entry in {
        503: 'payment_creation_pending',
        409: 'payment_creation_unknown',
      }.entries) {
        final result = await http.runWithClient(
          () => premium.startWebPayment(
            tier: PremiumTier.weekly,
            email: 'receipt@example.invalid',
          ),
          () => MockClient((request) async {
            expect(request.url.path, '/api/user/pay-intent');
            expect(request.headers['authorization'], 'Bearer session');
            return http.Response(
              jsonEncode({'code': entry.value, 'order': order}),
              entry.key,
            );
          }),
        );
        expect(result?.errorCode, entry.value);
        expect(result?.url, isNull);
        expect(result?.order, order);
        expect(
          await PendingPayment.current(
            ownerId: 'google_A',
            now: DateTime.now().add(const Duration(days: 3)),
          ),
          order,
        );
        expect(await PendingPayment.current(ownerId: 'google_B'), isNull);
        expect(premium.isPremium, isFalse);
      }
    },
  );
  test(
    'creating and unknown survive status checks and another account; confirmed clears only after verified sync',
    () async {
      await PendingPayment.remember(
        order,
        ownerId: 'google_A',
        keepUntilResolved: true,
      );
      var status = 'creating', checks = 0;
      await http.runWithClient(
        () async {
          for (final value in [
            'creating',
            'creation_unknown',
            'requires_refund',
            'mismatch',
          ]) {
            status = value;
            expect(await premium.checkPendingPayment(), value);
            expect(await PendingPayment.current(ownerId: 'google_A'), order);
          }
          for (final terminal in [
            'canceled',
            'failed',
            'chargebacked',
            'create_failed',
          ]) {
            status = terminal;
            expect(await premium.checkPendingPayment(), terminal);
            expect(await PendingPayment.current(ownerId: 'google_A'), isNull);
            await PendingPayment.remember(
              order,
              ownerId: 'google_A',
              keepUntilResolved: true,
            );
          }
          await auth.completeSignInForTesting(user('B'), 'credential');
          final before = checks;
          expect(await premium.checkPendingPayment(), isNull);
          expect(checks, before);
          await auth.completeSignInForTesting(user('A'), 'credential');
          expect(await PendingPayment.current(ownerId: 'google_A'), order);
          status = 'confirmed';
          expect(await premium.checkPendingPayment(), 'confirmed');
          expect(await PendingPayment.current(ownerId: 'google_A'), isNull);
          expect(premium.isPremium, isTrue);
        },
        () => MockClient((request) async {
          if (request.url.path == '/api/auth/session') {
            final profile = user(jsonDecode(request.body)['name']);
            return http.Response(
              jsonEncode({
                'user': profile.toMap(),
                'token': 'session',
                'expiresAt': expiry.toIso8601String(),
              }),
              200,
            );
          }
          if (request.url.path == '/api/user/pay-check') {
            checks++;
            expect(jsonDecode(request.body)['order'], order);
            return http.Response(
              jsonEncode({'ok': true, 'status': status}),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'ok': true,
              'isPremium': status == 'confirmed',
              'premiumExpiresAt': status == 'confirmed'
                  ? expiry.toIso8601String()
                  : null,
            }),
            200,
          );
        }),
      );
    },
  );
  testWidgets(
    'unknown creation shows selectable order/support instructions in every locale and disables another payment',
    (tester) async {
      try {
        for (final language in ['ru', 'en', 'kk']) {
          updateAppLocale(Locale(language));
          await http.runWithClient(
            () async {
              await tester.pumpWidget(
                MaterialApp(
                  locale: Locale(language),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: Scaffold(
                    body: Builder(
                      builder: (context) => TextButton(
                        onPressed: () => showWebPaymentDialog(
                          context: context,
                          tier: PremiumTier.weekly,
                          live: true,
                        ),
                        child: const Text('Open'),
                      ),
                    ),
                  ),
                ),
              );
              await tester.tap(find.text('Open'));
              await tester.pumpAndSettle();
              await tester.tap(find.text(appL10n.webPayProceed));
              await tester.pumpAndSettle();
              expect(
                find.text(appL10n.webPayCreationReview(order)),
                findsOneWidget,
              );
              final button = find.widgetWithText(
                TextButton,
                appL10n.webPayProceed,
              );
              expect(tester.widget<TextButton>(button).onPressed, isNull);
              expect(tester.takeException(), isNull);
              await tester.tap(find.text(appL10n.cancel));
              await tester.pumpAndSettle();
            },
            () => MockClient(
              (_) async => http.Response(
                jsonEncode({
                  'code': 'payment_creation_unknown',
                  'order': order,
                }),
                409,
              ),
            ),
          );
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
