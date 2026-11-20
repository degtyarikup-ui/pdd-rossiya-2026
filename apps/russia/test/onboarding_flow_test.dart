import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
// ignore: depend_on_referenced_packages
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/device_region.dart';
import 'package:pdd_app/data/services/iap_service.dart';
import 'package:pdd_app/data/services/install_reporter.dart';
import 'package:pdd_app/data/services/onboarding_service.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/main.dart';
import 'package:pdd_app/presentation/screens/home/home_screen.dart';
import 'package:pdd_app/presentation/screens/onboarding/onboarding_screen.dart';
import 'package:pdd_app/presentation/screens/settings/settings_screen.dart';
import 'package:pdd_app/presentation/widgets/premium_benefits_screen.dart';
import 'package:pdd_app/presentation/widgets/premium_celebration_screen.dart';
import 'package:pdd_app/presentation/widgets/premium_plans_sheet.dart';
import 'package:pdd_app/presentation/widgets/promo_code_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'iap_catalog_test.dart' show CatalogStore, playQuarter, product;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const capture = bool.fromEnvironment('PDD_CAPTURE_ONBOARDING');

  setUpAll(() async {
    await initAppDateFormatting();
    final fonts = FontLoader(AppTheme.fontFamily)
      ..addFont(rootBundle.load('assets/fonts/Onest-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Onest-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Onest-SemiBold.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Onest-Bold.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Onest-ExtraBold.ttf'));
    await fonts.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  setUp(() {
    IapService.instance.debugClearPriceCache();
    IapService.instance.products
      ..clear()
      ..addAll({
        IapService.productId3Months: ProductDetails(
          id: IapService.productId3Months,
          title: 'Quarter',
          description: 'Quarter',
          price: '290,00 ₽',
          rawPrice: 290,
          currencyCode: 'RUB',
        ),
        IapService.productIdWeek: ProductDetails(
          id: IapService.productIdWeek,
          title: 'Week',
          description: 'Week',
          price: '99,00 ₽',
          rawPrice: 99,
          currencyCode: 'RUB',
        ),
      });
  });

  tearDown(() {
    OnboardingService.instance.resetForTest();
    IapService.instance.products.clear();
    IapService.instance.debugClearPriceCache();
    debugDefaultTargetPlatformOverride = null;
    updateAppLocale(const Locale('ru'));
  });

  Future<void> precacheOnboardingAssets(WidgetTester tester) async {
    if (!capture) return;
    await tester.runAsync(() async {
      final ctx = tester.element(find.byType(OnboardingScreen));
      for (final p in CountryConfig.current.onboardingLearnerPhotos) {
        await precacheImage(AssetImage(p), ctx);
      }
      for (final g in [
        'assets/images/games/hub_crossroads.webp',
        'assets/images/games/hub_regulator.webp',
        'assets/images/games/hub_parking.webp',
        'assets/images/games/hub_road_signs.webp',
        'assets/images/onboarding_car.png',
        'assets/images/onboarding_truck.png',
        'assets/images/premium/hero.png',
      ]) {
        await precacheImage(AssetImage(g), ctx);
      }
    });
  }

  Future<void> capturePreview(
    WidgetTester tester,
    GlobalKey boundaryKey,
    String filename,
  ) async {
    if (!capture) return;
    if (find.byType(PremiumBenefitsScreen).evaluate().isNotEmpty) {
      await tester.runAsync(() async {
        final ctx = tester.element(find.byType(PremiumBenefitsScreen));
        final w = MediaQuery.sizeOf(
          ctx,
        ).width.clamp(0, 600).ceil().clamp(1, 1024);
        await precacheImage(
          ResizeImage(
            const AssetImage('assets/images/premium/hero.png'),
            width: w,
          ),
          ctx,
        );
        await Future<void>.delayed(const Duration(milliseconds: 120));
      });
      await tester.pumpAndSettle();
    }
    await tester.runAsync(() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.25);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final outFile = File('output/onboarding-preview/$filename.png');
      outFile.parent.createSync(recursive: true);
      outFile.writeAsBytesSync(byteData!.buffer.asUint8List());
      image.dispose();
    });
  }

  group('OnboardingService startup classification', () {
    test(
      'shows onboarding on fresh install and keeps unfinished state across cold restarts',
      () async {
        SharedPreferences.setMockInitialValues({});
        await InstallReporter.captureLaunchState();
        await OnboardingService.instance.init();

        expect(OnboardingService.instance.shouldShow, isTrue);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(OnboardingService.completedKey), isFalse);

        // Simulate UsageReporter/InstallReporter writing analytics keys before
        // the user finishes onboarding, followed by a cold app restart.
        await prefs.setString('usage_events_v1', '[{"id":"1"}]');
        await prefs.setString('install_id', 'inst_123');
        OnboardingService.instance.resetForTest();

        await OnboardingService.instance.init();
        expect(OnboardingService.instance.shouldShow, isTrue);
      },
    );

    test(
      'skips onboarding automatically for upgrading users with existing progress or auth',
      () async {
        for (final existingPrefs in <Map<String, Object>>[
          {'question_progress_ab': '{"1_1":true}'},
          {'app_settings': '{"ticketCategory":"cd"}'},
          {'streak_last_active': '2026-11-16'},
          {'install_reported': true},
          {'parking_progress': '{"bestScore":10}'},
        ]) {
          SharedPreferences.setMockInitialValues(existingPrefs);
          OnboardingService.instance.resetForTest();
          await OnboardingService.instance.init();
          expect(
            OnboardingService.instance.shouldShow,
            isFalse,
            reason: 'Expected skip for $existingPrefs',
          );
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.getBool(OnboardingService.completedKey), isTrue);
        }

        // Authenticated user on fresh storage (e.g. iOS Keychain session) skips too.
        SharedPreferences.setMockInitialValues({});
        OnboardingService.instance.resetForTest();
        await OnboardingService.instance.init(isAuthenticated: true);
        expect(OnboardingService.instance.shouldShow, isFalse);
      },
    );

    test('handles malformed preference types safely', () async {
      SharedPreferences.setMockInitialValues({
        OnboardingService.completedKey: 'not-a-bool',
        OnboardingService.dailyGoalKey: 'not-an-int',
      });
      await OnboardingService.instance.init();
      expect(OnboardingService.instance.shouldShow, isTrue);
      expect(OnboardingService.instance.pace, OnboardingPace.optimal);
    });
  });

  test(
    'all 10 generated Russian learner WebP photos are bundled and valid',
    () async {
      final photos = CountryConfig.current.onboardingLearnerPhotos;
      expect(photos, hasLength(10));
      for (final path in photos) {
        final bytes = (await rootBundle.load(path)).buffer.asUint8List();
        expect(
          bytes.length,
          greaterThan(5000),
          reason: 'Asset too small: $path',
        );
        // Verify RIFF....WEBP magic header
        expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
        expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WEBP');
      }
    },
  );

  void testWithStorePlatform(
    String description,
    WidgetTesterCallback callback,
  ) {
    testWidgets(description, (tester) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        await callback(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWithStorePlatform(
    'eligible first-time user sees the trial and renewal terms from onboarding',
    (tester) async {
      InAppPurchase.instance;
      final store = CatalogStore();
      InAppPurchasePlatform.instance = store;
      addTearDown(() => store.products.clear());
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      DeviceRegion.readPlayCountry = () async => 'DE';
      addTearDown(DeviceRegion.resetPlayCountry);
      const channel = MethodChannel('pdd/device_region');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => 'DE');
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      store.products = [
        product(IapService.productIdWeek),
        ...playQuarter(IapService.productId3Months, 3),
        ...playQuarter(IapService.productIdQuarterStandard, 4),
        ...playQuarter(IapService.productIdQuarterTrial, 4, withTrial: true),
      ];
      SharedPreferences.setMockInitialValues({});
      final source = ProgressDataSource();
      await source.init();
      await OnboardingService.instance.init();
      expect(OnboardingService.instance.shouldShow, isTrue);
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [progressDataSourceProvider.overrideWithValue(source)],
              child: MaterialApp(
                locale: const Locale('ru'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: AppTheme.lightTheme,
                home: OnboardingScreen(onCompleted: () {}),
              ),
            ),
          );
          await precacheOnboardingAssets(tester);
          for (var step = 0; step < 4; step++) {
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('onboarding-primary-cta')),
            );
          }
          await tester.pumpAndSettle();
          expect(find.text(appL10n.premiumTrialButton), findsOneWidget);
          expect(find.text(appL10n.onboardingContinueFree), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('premium-show-plans')));
          await tester.pumpAndSettle();
          expect(
            find.text(
              appL10n.premiumTrialTerms('€4', appL10n.paywallStoreGoogle),
            ),
            findsOneWidget,
          );
          expect(
            tester
                .widget<ElevatedButton>(
                  find.byKey(const ValueKey('premium-plans-purchase')),
                )
                .onPressed,
            isNotNull,
          );
          expect(store.launched, isNull);
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient((request) async {
          if (request.url.path != '/api/pay/catalog') {
            return http.Response('{}', 200);
          }
          return http.Response(
            jsonEncode({
              'version': 1,
              'tariffs': {
                'weekly': {'days': 7, 'priceRub': 99},
                'threeMonths': {'days': 90, 'priceRub': 370},
              },
              'storeTrials': {'googleplay': true},
              'nativeQuarter': {'googleplay': 'standard'},
            }),
            200,
          );
        }),
      );
    },
  );

  testWithStorePlatform(
    'completes 5-step onboarding with final Premium paywall, persists C/D + 30 min plan, and navigates to HomeScreen',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({
        'notification_prompt_shown': true,
      });
      final source = ProgressDataSource();
      await source.init();
      await OnboardingService.instance.init();
      expect(OnboardingService.instance.shouldShow, isTrue);

      final previewKey = GlobalKey();
      final fixedNow = DateTime(2026, 11, 18);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            progressDataSourceProvider.overrideWithValue(source),
            isAuthenticatedProvider.overrideWithValue(false),
            currentUserProvider.overrideWithValue(null),
            statsProvider.overrideWith(
              (_) async => {
                'correctAnswers': 0,
                'answeredQuestions': 0,
                'wrongQuestions': 0,
                'passedTickets': 0,
                'totalQuestions': 800,
                'totalTickets': 40,
              },
            ),
            unfinishedSessionProvider.overrideWith((_) async => null),
          ],
          child: RepaintBoundary(
            key: previewKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: const Locale('ru'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: AppTheme.lightTheme,
              home: _TestOnboardingHost(now: fixedNow),
            ),
          ),
        ),
      );

      await precacheOnboardingAssets(tester);
      await tester.pumpAndSettle();

      // Step 1: Social proof mosaic + verified Russian app metrics
      expect(find.byKey(const ValueKey('onboarding-step-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('onboarding-back')), findsNothing);
      expect(find.byKey(const ValueKey('onboarding-skip')), findsOneWidget);
      expect(find.text('4,7'), findsOneWidget);
      expect(find.text('96,8%'), findsOneWidget);
      expect(find.textContaining('ГИБДД'), findsOneWidget);
      expect(find.textContaining('800'), findsOneWidget);
      await capturePreview(tester, previewKey, 'light_step_1_learners');

      // Advance to Step 2: Topic tracking + weak spots + 3D City & games
      await tester.tap(find.byKey(const ValueKey('onboarding-primary-cta')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('onboarding-step-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('onboarding-back')), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('85%'), findsOneWidget);
      expect(find.text('60%'), findsOneWidget);
      expect(find.text('35%'), findsOneWidget);
      await capturePreview(tester, previewKey, 'light_step_2_smart_practice');

      // Verify back button returns to Step 1 and forward returns to Step 2
      await tester.tap(find.byKey(const ValueKey('onboarding-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('onboarding-step-0')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('onboarding-primary-cta')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('onboarding-step-1')), findsOneWidget);

      // Advance to Step 3: Personalize category & daily pace
      await tester.tap(find.byKey(const ValueKey('onboarding-primary-cta')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('onboarding-step-2')), findsOneWidget);
      await capturePreview(tester, previewKey, 'light_step_3_personalize');

      // Select C/D category and 30 min/day sprint pace
      await tester.tap(find.byKey(const ValueKey('onboarding-category-cd')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('onboarding-pace-30')));
      await tester.pumpAndSettle();

      // Advance to Step 4: Personal plan ready + Readiness Forecast curve
      await tester.tap(find.byKey(const ValueKey('onboarding-primary-cta')));
      // A second tap on the same rendered button must not skip the plan.
      await tester.tap(find.byKey(const ValueKey('onboarding-primary-cta')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('onboarding-step-3')), findsOneWidget);
      expect(find.textContaining('C/D'), findsOneWidget);
      expect(find.textContaining('40 билетов'), findsOneWidget);
      expect(find.textContaining('30 мин'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(
        (await source.loadAppSettings()).ticketCategory,
        TicketCategory.ab,
      );
      await capturePreview(tester, previewKey, 'light_step_4_plan_ready');

      // Advance to Step 5: Premium Paywall screen at the end of onboarding
      await tester.tap(find.byKey(const ValueKey('onboarding-primary-cta')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('onboarding-step-4')), findsOneWidget);
      expect(find.byType(PremiumBenefitsScreen), findsOneWidget);
      expect(find.text(appL10n.paywallTitle), findsOneWidget);
      expect(find.byKey(const ValueKey('premium-show-plans')), findsOneWidget);
      expect(find.text(appL10n.onboardingContinueFree), findsOneWidget);
      // The choices survive web sign-in and payment redirects from the offer.
      expect(OnboardingService.instance.shouldShow, isFalse);
      expect(
        (await source.loadAppSettings()).ticketCategory,
        TicketCategory.cd,
      );
      expect(OnboardingService.instance.dailyGoalMinutes, 30);
      await capturePreview(tester, previewKey, 'light_step_5_paywall');

      // Opening plans sheet works directly from the onboarding paywall
      await tester.tap(find.byKey(const ValueKey('premium-show-plans')));
      await tester.pumpAndSettle();
      expect(find.byType(PremiumPlansSheet), findsOneWidget);
      expect(find.text(appL10n.premiumPlansTitle), findsOneWidget);

      // Backing out of plans sheet keeps user on Step 5 Paywall
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PremiumPlansSheet), findsNothing);
      expect(find.byKey(const ValueKey('onboarding-step-4')), findsOneWidget);

      // System back on Step 5 Paywall returns to Step 4 Plan Ready
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('onboarding-step-3')), findsOneWidget);

      // The visible back button works on platforms without system back.
      await tester.tap(find.byKey(const ValueKey('onboarding-primary-cta')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('onboarding-step-4')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('onboarding-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('onboarding-step-3')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('onboarding-primary-cta')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('premium-dismiss-offer')));
      await tester.pumpAndSettle();

      // Verify transition to HomeScreen and persisted choices
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(OnboardingService.instance.shouldShow, isFalse);
      expect(OnboardingService.instance.dailyGoalMinutes, 30);
      final savedSettings = await source.loadAppSettings();
      expect(savedSettings.ticketCategory, TicketCategory.cd);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(OnboardingService.completedKey), isTrue);
      expect(prefs.getInt(OnboardingService.dailyGoalKey), 30);
      expect(tester.takeException(), isNull);
    },
  );

  testWithStorePlatform(
    'completing subscription on final onboarding paywall celebrates and enters HomeScreen',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({
        'notification_prompt_shown': true,
      });
      final source = ProgressDataSource();
      await source.init();
      await OnboardingService.instance.init();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            progressDataSourceProvider.overrideWithValue(source),
            isAuthenticatedProvider.overrideWithValue(false),
            currentUserProvider.overrideWithValue(null),
            statsProvider.overrideWith(
              (_) async => {
                'correctAnswers': 0,
                'answeredQuestions': 0,
                'wrongQuestions': 0,
                'passedTickets': 0,
                'totalQuestions': 800,
                'totalTickets': 40,
              },
            ),
            unfinishedSessionProvider.overrideWith((_) async => null),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.lightTheme,
            home: _TestOnboardingHost(now: DateTime(2026, 11, 18)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Advance through steps 0 -> 1 -> 2 -> 3 -> 4 (Paywall)
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const ValueKey('onboarding-primary-cta')));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const ValueKey('onboarding-step-4')), findsOneWidget);

      // Open plans and simulate completed purchase
      await tester.tap(find.byKey(const ValueKey('premium-show-plans')));
      await tester.pumpAndSettle();
      Navigator.of(
        tester.element(find.byType(PremiumPlansSheet)),
      ).pop(PremiumPlansResult.purchased);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 650));

      // Celebration appears before transitioning to HomeScreen
      expect(find.byType(PremiumCelebrationScreen), findsOneWidget);
      await tester.tap(find.text(appL10n.premiumCelebrationAction));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(OnboardingService.instance.shouldShow, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWithStorePlatform(
    'SBP browser handoff on final onboarding paywall finishes onboarding to HomeScreen',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({
        'notification_prompt_shown': true,
      });
      final source = ProgressDataSource();
      await source.init();
      await OnboardingService.instance.init();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            progressDataSourceProvider.overrideWithValue(source),
            isAuthenticatedProvider.overrideWithValue(false),
            currentUserProvider.overrideWithValue(null),
            statsProvider.overrideWith(
              (_) async => {
                'correctAnswers': 0,
                'answeredQuestions': 0,
                'wrongQuestions': 0,
                'passedTickets': 0,
                'totalQuestions': 800,
                'totalTickets': 40,
              },
            ),
            unfinishedSessionProvider.overrideWith((_) async => null),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.lightTheme,
            home: _TestOnboardingHost(now: DateTime(2026, 11, 18)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const ValueKey('onboarding-primary-cta')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('premium-show-plans')));
      await tester.pumpAndSettle();
      Navigator.of(
        tester.element(find.byType(PremiumPlansSheet)),
      ).pop(PremiumPlansResult.webPayment);
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(OnboardingService.instance.shouldShow, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'PddApp defers referral PromoCodeSheet until onboarding is skipped or completed',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({
        'notification_prompt_shown': true,
      });
      final source = ProgressDataSource();
      await source.init();
      await OnboardingService.instance.init();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            progressDataSourceProvider.overrideWithValue(source),
            isAuthenticatedProvider.overrideWithValue(false),
            currentUserProvider.overrideWithValue(null),
            statsProvider.overrideWith(
              (_) async => {
                'correctAnswers': 0,
                'answeredQuestions': 0,
                'wrongQuestions': 0,
                'passedTickets': 0,
                'totalQuestions': 800,
                'totalTickets': 40,
              },
            ),
            unfinishedSessionProvider.overrideWith((_) async => null),
          ],
          child: PddApp(referralPrompt: Future<bool>.value(true)),
        ),
      );
      await tester.pumpAndSettle();

      // PromoCodeSheet must NOT cover Step 1 of onboarding
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(PromoCodeSheet), findsNothing);

      // Skip onboarding -> lands on HomeScreen and opens deferred PromoCodeSheet
      await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(PromoCodeSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Settings debug preview uses defaults and preserves local choices',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({
        OnboardingService.completedKey: true,
        OnboardingService.dailyGoalKey: 30,
        'app_settings': '{"ticketCategory":"cd","languageCode":"ru"}',
        'notification_prompt_shown': true,
      });
      final source = ProgressDataSource();
      await source.init();
      await OnboardingService.instance.init(isAuthenticated: true);
      expect(OnboardingService.instance.shouldShow, isFalse);
      expect(OnboardingService.instance.dailyGoalMinutes, 30);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            progressDataSourceProvider.overrideWithValue(source),
            isAuthenticatedProvider.overrideWithValue(false),
            currentUserProvider.overrideWithValue(null),
            statsProvider.overrideWith(
              (_) async => {
                'correctAnswers': 0,
                'answeredQuestions': 0,
                'wrongQuestions': 0,
                'passedTickets': 0,
                'totalQuestions': 800,
                'totalTickets': 40,
              },
            ),
            unfinishedSessionProvider.overrideWith((_) async => null),
          ],
          child: const PddApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);

      // Navigate to Profile -> Settings -> tap Debug restart onboarding
      await tester.tap(find.text(appL10n.profile));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(SettingsScreen), findsOneWidget);

      final debugTile = find.byKey(
        const ValueKey('settings-debug-restart-onboarding'),
      );
      await tester.scrollUntilVisible(
        debugTile,
        200,
        scrollable: find.descendant(
          of: find.byType(SettingsScreen),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(debugTile);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('onboarding-step-0')), findsOneWidget);
      for (var step = 0; step < 3; step++) {
        await tester.tap(find.byKey(const ValueKey('onboarding-primary-cta')));
        await tester.pumpAndSettle();
      }
      expect(
        find.text(appL10n.onboardingPlanReadySubtitle('A/B', 15)),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(OnboardingService.instance.shouldShow, isFalse);
      expect(OnboardingService.instance.dailyGoalMinutes, 30);
      expect(
        (await source.loadAppSettings()).ticketCategory,
        TicketCategory.cd,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(OnboardingService.completedKey), isTrue);
      expect(prefs.getInt(OnboardingService.dailyGoalKey), 30);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final layout in [
    (
      name: 'pixel-9-pro-xl-dark-ru',
      size: const Size(448, 997),
      scale: 1.0,
      lang: 'ru',
      dark: true,
      disableAnimations: false,
      padding: const EdgeInsets.only(top: 48, bottom: 24),
    ),
    (
      name: 'tiny-large-text-kk',
      size: const Size(320, 480),
      scale: 2.0,
      lang: 'kk',
      dark: false,
      disableAnimations: false,
      padding: EdgeInsets.zero,
    ),
    (
      name: 'landscape-en',
      size: const Size(844, 390),
      scale: 1.0,
      lang: 'en',
      dark: false,
      disableAnimations: false,
      padding: EdgeInsets.zero,
    ),
    (
      name: 'dark-reduced-motion-ru',
      size: const Size(390, 844),
      scale: 1.0,
      lang: 'ru',
      dark: true,
      disableAnimations: true,
      padding: const EdgeInsets.only(top: 44, bottom: 34),
    ),
    (
      name: 'tablet-large-text-ru',
      size: const Size(768, 1024),
      scale: 1.6,
      lang: 'ru',
      dark: false,
      disableAnimations: false,
      padding: const EdgeInsets.only(top: 24, bottom: 20),
    ),
  ]) {
    testWithStorePlatform(
      'all 5 onboarding steps fit cleanly on ${layout.name}',
      (tester) async {
        updateAppLocale(Locale(layout.lang));
        tester.view.physicalSize = layout.size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        SharedPreferences.setMockInitialValues({});
        final source = ProgressDataSource();
        await source.init();
        OnboardingService.instance.resetForTest(shouldShow: true);

        final previewKey = GlobalKey();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [progressDataSourceProvider.overrideWithValue(source)],
            child: RepaintBoundary(
              key: previewKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: Locale(layout.lang),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: layout.dark ? AppTheme.darkTheme : AppTheme.lightTheme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(layout.scale),
                    disableAnimations: layout.disableAnimations,
                    padding: layout.padding,
                    viewPadding: layout.padding,
                  ),
                  child: child!,
                ),
                home: OnboardingScreen(
                  now: DateTime(2026, 11, 18),
                  onCompleted: () {},
                ),
              ),
            ),
          ),
        );
        await precacheOnboardingAssets(tester);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        if (capture && layout.name == 'pixel-9-pro-xl-dark-ru') {
          await capturePreview(tester, previewKey, 'pixel_dark_step_1');
        }

        for (var step = 1; step <= 4; step++) {
          await tester.tap(
            find.byKey(const ValueKey('onboarding-primary-cta')),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'Failed on step $step in ${layout.name}',
          );
          if (capture && layout.name == 'pixel-9-pro-xl-dark-ru') {
            await capturePreview(
              tester,
              previewKey,
              'pixel_dark_step_${step + 1}',
            );
          }
        }

        expect(find.byKey(const ValueKey('onboarding-step-4')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('premium-dismiss-offer')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _TestOnboardingHost extends StatefulWidget {
  const _TestOnboardingHost({required this.now});

  final DateTime now;

  @override
  State<_TestOnboardingHost> createState() => _TestOnboardingHostState();
}

class _TestOnboardingHostState extends State<_TestOnboardingHost> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    if (_done) return const HomeScreen();
    return OnboardingScreen(
      now: widget.now,
      onCompleted: () => setState(() => _done = true),
    );
  }
}
