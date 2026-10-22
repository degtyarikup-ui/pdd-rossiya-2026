import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/services/iap_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/premium_benefits_screen.dart';
import 'package:pdd_app/presentation/widgets/premium_paywall_sheet.dart';
import 'package:pdd_app/presentation/widgets/premium_plans_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Optional visual review output, deliberately excluded from golden assertions:
// flutter test test/premium_redesign_test.dart --dart-define=PREMIUM_CAPTURE=true
const _capture = bool.fromEnvironment('PREMIUM_CAPTURE');
const _captureKey = ValueKey('premium-review-boundary');
const _openKey = ValueKey('open-premium');
const _showPlans = ValueKey('premium-show-plans');
const _closePlans = ValueKey('premium-plans-close');

void _testPremium(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await callback(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Real application fonts exercise the actual line lengths in all locales.
    final loader = FontLoader('Onest');
    for (final weight in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
    ]) {
      loader.addFont(rootBundle.load('assets/fonts/Onest-$weight.ttf'));
    }
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
    IapService.instance.products.clear();
    IapService.instance.debugClearPriceCache();
    debugDefaultTargetPlatformOverride = null;
    updateAppLocale(const Locale('ru'));
  });

  Future<void> mount(
    WidgetTester tester, {
    String language = 'ru',
    Size size = const Size(390, 844),
    double textScale = 1,
    bool dark = false,
    ValueChanged<bool?>? onResult,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    updateAppLocale(Locale(language));
    await tester.pumpWidget(
      RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: true,
              padding: const EdgeInsets.only(top: 24, bottom: 24),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  key: _openKey,
                  onPressed: () async {
                    final result = await PremiumPaywallSheet.show(context);
                    onResult?.call(result);
                  },
                  child: const Text('Open premium'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(_openKey));
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!_capture) return;
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('assets/images/premium/hero.png'),
        tester.element(find.byType(PremiumBenefitsScreen)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_captureKey),
      );
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final dir = Directory('scratch/premium')..createSync(recursive: true);
      await File('${dir.path}/$name.png').writeAsBytes(
        bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    });
  }

  for (final language in ['ru', 'en', 'kk']) {
    for (final configuration in [
      (size: const Size(390, 844), scale: 1.0, dark: false, name: 'phone'),
      (size: const Size(320, 568), scale: 2.0, dark: true, name: 'large-text'),
      (size: const Size(844, 390), scale: 1.0, dark: false, name: 'landscape'),
      (size: const Size(1024, 768), scale: 1.0, dark: true, name: 'tablet'),
    ]) {
      _testPremium(
        '$language ${configuration.name}: benefits and plans adapt without overflow',
        (tester) async {
          await mount(
            tester,
            language: language,
            size: configuration.size,
            textScale: configuration.scale,
            dark: configuration.dark,
          );
          expect(find.text(appL10n.paywallTitle), findsOneWidget);
          final titleParagraph = tester.renderObject<RenderParagraph>(
            find.text(appL10n.paywallTitle),
          );
          for (final word in RegExp(r'\S+').allMatches(appL10n.paywallTitle)) {
            expect(
              titleParagraph.getBoxesForSelection(
                TextSelection(baseOffset: word.start, extentOffset: word.end),
              ),
              hasLength(1),
              reason: 'The benefits headline keeps each localized word whole',
            );
          }
          expect(find.text(appL10n.premiumRatingValue), findsOneWidget);
          expect(find.text(appL10n.premiumPassRateValue), findsOneWidget);
          for (final value in [
            appL10n.premiumRatingValue,
            appL10n.premiumPassRateValue,
          ]) {
            final paragraph = tester.renderObject<RenderParagraph>(
              find.text(value),
            );
            expect(
              paragraph.getBoxesForSelection(
                TextSelection(baseOffset: 0, extentOffset: value.length),
              ),
              hasLength(1),
              reason: 'A statistic and its percent sign stay together',
            );
          }
          expect(find.byType(PremiumPlansSheet), findsNothing);
          expect(find.text('290,00 ₽'), findsNothing);
          expect(find.byKey(_showPlans).hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);

          if (configuration.name == 'phone' ||
              (language == 'kk' && configuration.name == 'large-text')) {
            await capture(tester, 'benefits-$language-${configuration.name}');
          }

          // The last benefit remains reachable even when text doubles or the
          // viewport becomes landscape; the fixed CTA stays in the safe area.
          await tester.ensureVisible(
            find.text(appL10n.premiumBenefitFeedTitle),
          );
          await tester.pumpAndSettle();
          final lastBenefit = tester.getRect(
            find.text(appL10n.premiumBenefitFeedTitle),
          );
          final cta = tester.getRect(find.byKey(_showPlans));
          expect(lastBenefit.top, greaterThanOrEqualTo(0));
          expect(lastBenefit.bottom, lessThanOrEqualTo(cta.top));
          expect(find.byKey(_showPlans).hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.tap(find.byKey(_showPlans));
          await tester.pumpAndSettle();
          expect(find.byType(PremiumPlansSheet), findsOneWidget);
          expect(find.text(appL10n.premiumPlansTitle), findsOneWidget);
          expect(find.text('290,00 ₽'), findsOneWidget);
          expect(find.text('99,00 ₽'), findsOneWidget);
          expect(tester.takeException(), isNull);

          if (configuration.name == 'phone' ||
              (language == 'kk' && configuration.name == 'large-text')) {
            await capture(tester, 'plans-$language-${configuration.name}');
          }

          await tester.ensureVisible(
            find.byKey(const ValueKey('premium-plans-purchase')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('premium-plans-purchase')).hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  _testPremium('closing or backing out of plans preserves the benefits route', (
    tester,
  ) async {
    var completed = false;
    bool? result;
    await mount(
      tester,
      onResult: (value) {
        completed = true;
        result = value;
      },
    );

    await tester.tap(find.byKey(_showPlans));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_closePlans));
    await tester.pumpAndSettle();
    expect(find.byType(PremiumPlansSheet), findsNothing);
    expect(find.byType(PremiumBenefitsScreen), findsOneWidget);
    expect(completed, isFalse);

    await tester.tap(find.byKey(_showPlans));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PremiumPlansSheet), findsNothing);
    expect(find.byType(PremiumBenefitsScreen), findsOneWidget);
    expect(completed, isFalse);

    await tester.tap(find.byKey(const ValueKey('premium-close-benefits')));
    await tester.pumpAndSettle();
    expect(find.byType(PremiumBenefitsScreen), findsNothing);
    expect(completed, isTrue);
    expect(result, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final result in [true, false]) {
    _testPremium('plan result $result reaches the original premium gate', (
      tester,
    ) async {
      var completed = false;
      bool? gateResult;
      await mount(
        tester,
        onResult: (value) {
          completed = true;
          gateResult = value;
        },
      );
      await tester.tap(find.byKey(_showPlans));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(PremiumPlansSheet))).pop(result);
      await tester.pumpAndSettle();
      expect(find.byType(PremiumPlansSheet), findsNothing);
      expect(find.byType(PremiumBenefitsScreen), findsNothing);
      expect(find.byType(PremiumPaywallSheet), findsNothing);
      expect(completed, isTrue);
      expect(gateResult, result);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
