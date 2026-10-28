import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/services/iap_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';
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

void _expectBenefitEmphasis(WidgetTester tester) {
  final muted = AppColors.white.withValues(alpha: .4);
  final games = find.byWidgetPredicate(
    (widget) =>
        widget is RichText &&
        widget.text.toPlainText().contains(appL10n.premiumBenefitGamesTitle) &&
        widget.text.toPlainText().contains(appL10n.premiumBenefitGamesDetail),
  );
  expect(games, findsOneWidget);
  final paragraph = tester.renderObject<RenderParagraph>(games);
  final runs = <(String, TextStyle)>[];
  void collect(InlineSpan span, TextStyle inherited) {
    final effective = inherited.merge(span.style);
    if (span is TextSpan) {
      if (span.text case final String text when text.trim().isNotEmpty) {
        runs.add((text.trim(), effective));
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        collect(child, effective);
      }
    }
  }

  collect(paragraph.text, const TextStyle());
  expect(runs, hasLength(2));
  expect(runs[0].$1, appL10n.premiumBenefitGamesTitle);
  expect(runs[0].$2.color, AppColors.white);
  expect(runs[1].$1, appL10n.premiumBenefitGamesDetail);
  expect(runs[1].$2.color, muted);
  expect(runs[0].$2.fontSize, runs[1].$2.fontSize);
  expect(runs[0].$2.fontWeight, runs[1].$2.fontWeight);

  for (final benefit in [
    (
      title: appL10n.premiumBenefitAiTitle,
      detail: appL10n.premiumBenefitAiDetail,
      titleColor: AppColors.white,
      detailColor: muted,
    ),
    (
      title: appL10n.premiumBenefitVoiceTitle,
      detail: appL10n.premiumBenefitVoiceDetail,
      titleColor: muted,
      detailColor: AppColors.white,
    ),
    (
      title: appL10n.premiumBenefitFeedTitle,
      detail: appL10n.premiumBenefitFeedDetail,
      titleColor: muted,
      detailColor: AppColors.white,
    ),
  ]) {
    final title = tester.widget<Text>(find.text(benefit.title));
    final detail = tester.widget<Text>(find.text(benefit.detail));
    expect(title.style?.color, benefit.titleColor);
    expect(detail.style?.color, benefit.detailColor);
    expect(title.style?.fontSize, detail.style?.fontSize);
    expect(title.style?.fontWeight, detail.style?.fontWeight);
  }
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
    bool reducedMotion = true,
    bool settle = true,
    String? lockedGame,
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
              disableAnimations: reducedMotion,
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
                    final result = await PremiumPaywallSheet.show(
                      context,
                      lockedGame: lockedGame,
                    );
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
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
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
          expect(find.text(appL10n.paywallFreeNote), findsNothing);
          _expectBenefitEmphasis(tester);
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
            find.text(appL10n.premiumBenefitFeedDetail),
          );
          await tester.pumpAndSettle();
          final lastBenefit = tester.getRect(
            find.text(appL10n.premiumBenefitFeedDetail),
          );
          final cta = tester.getRect(find.byKey(_showPlans));
          expect(
            cta.width,
            closeTo(configuration.size.width.clamp(0, 600) - 40, 1),
          );
          expect(lastBenefit.top, greaterThanOrEqualTo(0));
          expect(lastBenefit.bottom, lessThanOrEqualTo(cta.top));
          expect(find.byKey(_showPlans).hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.tap(find.byKey(_showPlans));
          await tester.pumpAndSettle();
          expect(find.byType(PremiumPlansSheet), findsOneWidget);
          expect(find.text(appL10n.premiumPlansTitle), findsOneWidget);
          expect(find.text(appL10n.paywallFreeNote), findsNothing);
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

  double revealOpacity(WidgetTester tester, String name) => tester
      .widget<FadeTransition>(
        find.descendant(
          of: find.byKey(ValueKey('premium-reveal-$name')),
          matching: find.byType(FadeTransition),
        ),
      )
      .opacity
      .value;

  _testPremium(
    'benefits enter in order and stay revealed after closing plans',
    (tester) async {
      await mount(tester, reducedMotion: false, settle: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(revealOpacity(tester, 'title'), greaterThan(0));
      expect(revealOpacity(tester, 'ai'), 0);
      expect(revealOpacity(tester, 'feed'), 0);
      expect(find.byKey(_showPlans).hitTestable(), findsNothing);
      await tester.pump(const Duration(milliseconds: 100));
      expect(revealOpacity(tester, 'ai'), greaterThan(0));
      expect(revealOpacity(tester, 'feed'), 0);
      await tester.pump(const Duration(milliseconds: 500));
      expect(revealOpacity(tester, 'feed'), 1);
      expect(find.byKey(_showPlans).hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(_showPlans));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_closePlans));
      await tester.pumpAndSettle();
      expect(revealOpacity(tester, 'title'), 1);
      expect(revealOpacity(tester, 'feed'), 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  _testPremium('reduced motion shows benefits immediately', (tester) async {
    await mount(tester, settle: false);
    // Leave the native route's initial offstage frame, without waiting for
    // the content entrance animation.
    await tester.pump(const Duration(milliseconds: 16));
    for (final name in [
      'hero',
      'title',
      'stats',
      'games',
      'ai',
      'voice',
      'feed',
      'cta',
    ]) {
      expect(revealOpacity(tester, name), 1);
    }
    expect(find.text(appL10n.premiumRatingValue), findsOneWidget);
    expect(find.text(appL10n.premiumPassRateValue), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final language in ['ru', 'en', 'kk']) {
    for (final configuration in [
      (size: const Size(390, 844), scale: 1.0, name: 'phone'),
      (size: const Size(320, 568), scale: 2.0, name: 'large-text'),
    ]) {
      _testPremium(
        '$language ${configuration.name}: a locked game is named above the title',
        (tester) async {
          await mount(
            tester,
            language: language,
            size: configuration.size,
            textScale: configuration.scale,
          );
          // The generic paywall keeps its layout without the note.
          expect(
            find.byKey(const ValueKey('premium-locked-game')),
            findsNothing,
          );
          final plainTitle = tester.getTopLeft(find.text(appL10n.paywallTitle));
          Navigator.of(
            tester.element(find.byType(PremiumBenefitsScreen)),
          ).pop();
          await tester.pumpAndSettle();

          await mount(
            tester,
            language: language,
            size: configuration.size,
            textScale: configuration.scale,
            lockedGame: appL10n.gamesParkingTitle,
          );
          final note = find.byKey(const ValueKey('premium-locked-game'));
          expect(note, findsOneWidget);
          expect(
            find.text(appL10n.paywallLockedGame(appL10n.gamesParkingTitle)),
            findsOneWidget,
          );
          final title = tester.getRect(find.text(appL10n.paywallTitle));
          final noteRect = tester.getRect(note);
          expect(noteRect.bottom, lessThanOrEqualTo(title.top));
          expect(noteRect.left, greaterThanOrEqualTo(0));
          expect(noteRect.right, lessThanOrEqualTo(configuration.size.width));
          expect(title.top, greaterThan(plainTitle.dy));
          expect(tester.takeException(), isNull);
          await capture(tester, 'locked-game-$language-${configuration.name}');
        },
      );
    }
  }

  for (final language in ['ru', 'en', 'kk']) {
    _testPremium('statistics count up without shifting in $language', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await mount(
          tester,
          language: language,
          reducedMotion: false,
          settle: false,
        );
        await tester.pump(const Duration(milliseconds: 16));
        final rating = find.byKey(const ValueKey('premium-rating-value'));
        final passRate = find.byKey(const ValueKey('premium-pass-value'));
        String displayed(Finder parent) => tester
            .widget<Text>(
              find.descendant(of: parent, matching: find.byType(Text)),
            )
            .data!;
        double number(Finder parent) => double.parse(
          displayed(parent).replaceAll('%', '').replaceAll(',', '.'),
        );

        expect(number(rating), 1);
        expect(number(passRate), 1);
        final ratingWidth = tester.getSize(rating).width;
        final passWidth = tester.getSize(passRate).width;
        final ratingX = tester.getTopLeft(rating).dx;
        final passX = tester.getTopLeft(passRate).dx;
        await tester.pump(const Duration(milliseconds: 250));
        final intermediateRating = number(rating);
        final intermediatePass = number(passRate);
        expect(intermediateRating, inExclusiveRange(1, 4.7));
        expect(intermediatePass, inExclusiveRange(1, 96.8));
        expect(
          displayed(rating).contains(language == 'en' ? '.' : ','),
          isTrue,
        );
        expect(
          find.bySemanticsLabel(
            '${appL10n.premiumRatingValue}, ${appL10n.premiumRatingLabel}',
          ),
          findsOneWidget,
        );
        await tester.pump(const Duration(milliseconds: 250));
        expect(number(rating), greaterThan(intermediateRating));
        expect(number(passRate), greaterThan(intermediatePass));
        await tester.pumpAndSettle();
        expect(displayed(rating), appL10n.premiumRatingValue);
        expect(displayed(passRate), appL10n.premiumPassRateValue);
        expect(tester.getSize(rating).width, ratingWidth);
        expect(tester.getSize(passRate).width, passWidth);
        expect(tester.getTopLeft(rating).dx, ratingX);
        expect(tester.getTopLeft(passRate).dx, passX);
        await tester.tap(find.byKey(_showPlans));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(_closePlans));
        await tester.pumpAndSettle();
        expect(displayed(rating), appL10n.premiumRatingValue);
        expect(displayed(passRate), appL10n.premiumPassRateValue);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        semantics.dispose();
      }
    });
  }

  _testPremium('benefits use the common close control and yellow rating star', (
    tester,
  ) async {
    await mount(tester);
    final close = find.byKey(const ValueKey('premium-close-benefits'));
    expect(tester.widget(close), isA<AppChromeIconButton>());
    expect(tester.getSize(close), const Size.square(40));
    final star = tester.widget<SvgPicture>(
      find.byWidgetPredicate(
        (widget) => widget is SvgPicture && widget.colorFilter != null,
      ),
    );
    expect(
      star.colorFilter,
      const ColorFilter.mode(Color(0xFFFFEA00), BlendMode.srcIn),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

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

    await tester.tap(find.byKey(_showPlans));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
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
