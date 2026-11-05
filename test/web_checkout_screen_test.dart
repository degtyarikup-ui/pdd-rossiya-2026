import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/pending_payment.dart';
import 'package:pdd_app/data/services/install_reporter.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/premium_web_checkout_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = AuthService.instance;
  const order = '11111111-1111-4111-8111-111111111111';
  UserProfile user(String id) => UserProfile(
    id: 'google_$id',
    name: 'User $id',
    email: '$id@example.com',
    provider: AuthProviderType.google,
    createdAt: DateTime(2026),
  );
  http.Response response(Object data, [int status = 200]) =>
      http.Response(jsonEncode(data), status);
  Future<http.Response> standard(http.Request request) async {
    final path = request.url.path;
    if (path == '/api/auth/session') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final id = body['credential'] as String;
      return response({
        'user': user(id).toMap(),
        'token': 'session_$id',
        'expiresAt': DateTime.now()
            .add(const Duration(days: 30))
            .toIso8601String(),
      });
    }
    if (path == '/api/pay/status') return response({'available': true});
    if (path == '/api/user/pay-check') return response({'status': 'none'});
    return response({'ok': true, 'isPremium': false});
  }

  setUpAll(() async {
    PackageInfo.setMockInitialValues(
      appName: 'PDD test',
      packageName: 'pdd.test',
      version: '1.0',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await http.runWithClient(() async {
      await PremiumService.instance.init();
      await auth.init();
      await InstallReporter.clientMetadata();
    }, () => MockClient(standard));
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    updateAppLocale(const Locale('ru'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('pdd/device_region'),
          (_) async => 'RU',
        );
    await http.runWithClient(
      () => auth.completeSignInForTesting(user('A'), 'A'),
      () => MockClient(standard),
    );
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('pdd/device_region'),
          null,
        );
  });
  Widget page({
    PremiumWebCheckoutScreen? screen,
    double scale = 1,
    bool disableAnimations = true,
    bool dark = false,
    Locale locale = const Locale('ru'),
  }) => MaterialApp(
    theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        disableAnimations: disableAnimations,
      ),
      child: child!,
    ),
    home: screen ?? const PremiumWebCheckoutScreen(),
  );
  Finder key(String name) => find.byKey(ValueKey(name));
  Future<void> confirm(WidgetTester tester) async {
    await tester.ensureVisible(key('checkout-confirm-account'));
    await tester.tap(key('checkout-confirm-account'));
    await tester.pump();
    await tester.ensureVisible(key('checkout-pay'));
  }

  testWidgets(
    'guests see sign-in only; successful login reveals profile and plans, logout hides them',
    (tester) async {
      await http.runWithClient(() async {
        await tester.runAsync(auth.signOut);
        await tester.pumpWidget(page());
        await tester.pumpAndSettle();
        expect(find.text('Премиум доступ'), findsOneWidget);
        expect(find.text(appL10n.checkoutSignInTitle), findsOneWidget);
        expect(
          tester.widget<Semantics>(key('checkout-stage-0')).properties.selected,
          isTrue,
        );
        // Upcoming tabs describe progress; they cannot bypass sign-in.
        await tester.tap(key('checkout-stage-1'));
        await tester.pump();
        expect(key('checkout-plan-weekly'), findsNothing);
        expect(key('checkout-pay'), findsNothing);
        expect(key('checkout-email'), findsNothing);
        expect(key('checkout-account'), findsNothing);
        await tester.runAsync(
          () => auth.completeSignInForTesting(user('A'), 'A'),
        );
        await tester.pumpAndSettle();
        expect(key('checkout-account'), findsOneWidget);
        expect(
          tester.widget<Semantics>(key('checkout-stage-1')).properties.selected,
          isTrue,
        );
        expect(find.text(appL10n.checkoutSignInTitle), findsNothing);
        expect(key('checkout-plan-weekly'), findsOneWidget);
        expect(key('checkout-pay'), findsOneWidget);
        await tester.runAsync(auth.signOut);
        await tester.pumpAndSettle();
        expect(key('checkout-plan-weekly'), findsNothing);
        expect(key('checkout-pay'), findsNothing);
        expect(key('checkout-email'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }, () => MockClient(standard));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'explicit account confirmation and double tap create one charge for the selected plan',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var creates = 0, opened = 0;
      final pending = Completer<http.Response>();
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            page(
              screen: PremiumWebCheckoutScreen(
                initialTier: PremiumTier.weekly,
                openPayment: (_) async {
                  opened++;
                  return false;
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.widget<ElevatedButton>(key('checkout-pay')).onPressed,
            isNull,
          );
          await confirm(tester);
          expect(
            tester.widget<ElevatedButton>(key('checkout-pay')).onPressed,
            isNotNull,
          );
          await tester.tap(key('checkout-pay'));
          await tester.tap(key('checkout-pay'));
          await tester.pump();
          expect(creates, 1);
          pending.complete(
            response({
              'available': true,
              'order': order,
              'url': 'https://pay.platega.io/test',
            }),
          );
          await tester.pumpAndSettle();
          expect(opened, 1);
          expect(key('checkout-result'), findsOneWidget);
          expect(key('checkout-pay'), findsNothing);
          expect(await PendingPayment.current(ownerId: 'google_A'), order);
          expect(PremiumService.instance.isPremium, isFalse);
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient((request) async {
          if (request.url.path == '/api/user/pay-intent') {
            creates++;
            final data = jsonDecode(request.body) as Map<String, dynamic>;
            expect(data['tier'], 'weekly');
            expect(data['email'], 'A@example.com');
            expect(request.headers['authorization'], 'Bearer session_A');
            return pending.future;
          }
          return standard(request);
        }),
      );
      debugDefaultTargetPlatformOverride = null;
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('server recovers a pending order after local storage is lost', (
    tester,
  ) async {
    var creates = 0;
    await http.runWithClient(
      () async {
        await tester.pumpWidget(page());
        await tester.pumpAndSettle();
        expect(key('checkout-result'), findsOneWidget);
        expect(key('checkout-pay'), findsNothing);
        expect(find.text(appL10n.checkoutContinue), findsOneWidget);
        expect(creates, 0);
        expect(PremiumService.instance.isPremium, isFalse);
        await tester.pumpWidget(const SizedBox());
      },
      () => MockClient((request) async {
        if (request.url.path == '/api/user/pay-intent') creates++;
        if (request.url.path == '/api/user/pay-check') {
          expect(jsonDecode(request.body), {'current': true});
          return response({
            'status': 'pending',
            'order': order,
            'url': 'https://pay.platega.io/recovered',
          });
        }
        return standard(request);
      }),
    );
  });

  testWidgets(
    'failed redirect cannot declare cancellation or success; server is authoritative',
    (tester) async {
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            page(
              screen: const PremiumWebCheckoutScreen(
                paymentReturn: (result: 'failed', order: order),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(appL10n.webPayPending), findsOneWidget);
          expect(
            tester
                .widget<Semantics>(key('checkout-stage-1'))
                .properties
                .selected,
            isTrue,
          );
          expect(
            tester
                .widget<Semantics>(key('checkout-stage-2'))
                .properties
                .selected,
            isFalse,
          );
          expect(find.text(appL10n.checkoutCanceled), findsNothing);
          expect(find.text(appL10n.checkoutPaid), findsNothing);
          expect(PremiumService.instance.isPremium, isFalse);
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient(
          (request) async => request.url.path == '/api/user/pay-check'
              ? response({'status': 'pending', 'order': order})
              : standard(request),
        ),
      );
    },
  );

  testWidgets(
    'switching accounts resets confirmation and ignores the old account result',
    (tester) async {
      final delayed = Completer<http.Response>();
      await http.runWithClient(
        () async {
          await tester.pumpWidget(page());
          await tester.pumpAndSettle();
          await confirm(tester);
          expect(
            tester.widget<ElevatedButton>(key('checkout-pay')).onPressed,
            isNotNull,
          );
          // Server account changes elsewhere while this page is still mounted.
          await tester.runAsync(
            () => auth.completeSignInForTesting(user('B'), 'B'),
          );
          await tester.pump();
          expect(
            tester
                .widget<CheckboxListTile>(key('checkout-confirm-account'))
                .value,
            isFalse,
          );
          expect(
            tester.widget<ElevatedButton>(key('checkout-pay')).onPressed,
            isNull,
          );
          await tester.runAsync(
            () => auth.completeSignInForTesting(user('C'), 'C'),
          );
          delayed.complete(response({'status': 'confirmed', 'order': order}));
          await tester.pumpAndSettle();
          expect(find.text(appL10n.checkoutPaid), findsNothing);
          expect(auth.currentUser!.id, 'google_C');
          expect(PremiumService.instance.isPremium, isFalse);
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient((request) async {
          if (request.url.path == '/api/user/pay-check' &&
              request.headers['authorization'] == 'Bearer session_B') {
            return delayed.future;
          }
          return standard(request);
        }),
      );
    },
  );

  testWidgets('only server confirmation completes the final stage', (
    tester,
  ) async {
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          page(
            screen: const PremiumWebCheckoutScreen(
              paymentReturn: (result: 'done', order: order),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // Package/device metadata may finish on the platform event loop.
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();
        expect(
          tester.widget<Semantics>(key('checkout-stage-2')).properties.selected,
          isTrue,
        );
        expect(
          tester.widget<Semantics>(key('checkout-stage-1')).properties.value,
          appL10n.checkoutStageCompleted,
        );
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          AppColors.premiumLime,
        );
        expect(
          find.text(appL10n.premiumCelebrationPurchasedTitle),
          findsOneWidget,
        );
        expect(find.text(appL10n.checkoutAccountPaid), findsOneWidget);
        expect(key('checkout-pay'), findsNothing);
        expect(key('checkout-confirm-account'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
      () => MockClient((request) async {
        if (request.url.path == '/api/user/pay-check') {
          return response({'status': 'confirmed', 'order': order});
        }
        if (request.url.path == '/api/user/sync') {
          return response({'ok': true, 'isPremium': true});
        }
        return standard(request);
      }),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'animated artwork survives account changes and stops in background',
    (tester) async {
      await http.runWithClient(() async {
        await tester.pumpWidget(page(disableAnimations: false));
        await tester.pump(const Duration(seconds: 1));
        expect(key('premium-car-arrival'), findsOneWidget);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.runAsync(auth.signOut);
        await tester.pump(const Duration(seconds: 1));
        expect(find.text(appL10n.checkoutSignInTitle), findsOneWidget);
        expect(key('checkout-pay'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }, () => MockClient(standard));
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in const [Locale('ru'), Locale('en'), Locale('kk')]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('checkout fits 320px with $locale at text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        updateAppLocale(locale);
        await http.runWithClient(() async {
          await tester.pumpWidget(page(scale: scale, locale: locale));
          await tester.pumpAndSettle();
          await tester.ensureVisible(key('checkout-pay'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.runAsync(auth.signOut);
          await tester.pumpAndSettle();
          expect(find.text(appL10n.checkoutSignInTitle), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }, () => MockClient(standard));
      });
    }
  }
}
