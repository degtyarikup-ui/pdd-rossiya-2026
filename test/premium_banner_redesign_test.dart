import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/premium_banner_card.dart';

void main() {
  Future<void> showBanner(
    WidgetTester tester, {
    bool premium = false,
    int remaining = 5,
    bool disableAnimations = true,
    double textScale = 1,
    double width = 353,
    String language = 'ru',
  }) => tester.pumpWidget(
    ProviderScope(
      overrides: [
        isPremiumProvider.overrideWithValue(premium),
        dailyCardsRemainingProvider.overrideWithValue(remaining),
        dailyFreeLimitProvider.overrideWithValue(5),
      ],
      child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: disableAnimations,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(width: width, child: const PremiumBannerCard()),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('free allowance does not change the two banner states', (
    tester,
  ) async {
    for (final remaining in [5, 0]) {
      await showBanner(tester, remaining: remaining);
      await tester.pumpAndSettle();
      final material = tester.widget<Material>(
        find.byKey(const ValueKey('premium-banner-free')),
      );
      expect(material.color, AppColors.accent);
      expect(find.text(appL10n.premiumBannerSubtitle), findsOneWidget);
      expect(
        find.text(appL10n.premiumBannerCardsLeft(remaining, 5)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
    await showBanner(tester, premium: true);
    await tester.pumpAndSettle();
    final material = tester.widget<Material>(
      find.byKey(const ValueKey('premium-banner-active')),
    );
    expect(material.color, AppColors.premiumLime);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rays rotate slowly and stop for reduced motion', (tester) async {
    await showBanner(tester, disableAnimations: false);
    await tester.pump();
    final finder = find.byKey(const ValueKey('premium-banner-rays'));
    double turns() => tester.widget<RotationTransition>(finder).turns.value;
    final initial = turns();
    await tester.pump(const Duration(seconds: 2));
    expect(turns(), greaterThan(initial));
    expect(turns() - initial, closeTo(2 / 80, 0.001));

    await showBanner(tester);
    await tester.pumpAndSettle();
    final stopped = turns();
    await tester.pump(const Duration(seconds: 2));
    expect(turns(), stopped);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('car arrives from the right once and settles without overshoot', (
    tester,
  ) async {
    await showBanner(tester, disableAnimations: false);
    final car = find.byKey(const ValueKey('premium-car-arrival'));
    double x() => tester.widget<Transform>(car).transform.storage[12];
    final start = x();
    expect(start, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 250));
    expect(x(), inExclusiveRange(0, start));
    await tester.pump(const Duration(milliseconds: 600));
    expect(x(), closeTo(0, .001));
    await tester.pump(const Duration(milliseconds: 250));
    expect(x(), closeTo(0, .001));
    await showBanner(tester);
    await tester.pumpAndSettle();
    expect(x(), 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('text stays clear of the car across widths, locales and scales', (
    tester,
  ) async {
    for (final language in ['ru', 'en', 'kk']) {
      for (final premium in [false, true]) {
        for (final width in [280.0, 320.0, 353.0, 390.0, 400.0, 480.0, 600.0]) {
          for (final scale in [1.0, 1.3, 2.0]) {
            await showBanner(
              tester,
              language: language,
              premium: premium,
              width: width,
              textScale: scale,
            );
            await tester.pumpAndSettle();
            final car = tester.getRect(
              find.descendant(
                of: find.byKey(const ValueKey('premium-car-arrival')),
                matching: find.byType(Image),
              ),
            );
            final banner = tester.getRect(find.byType(PremiumBannerCard));
            for (final text in find.byType(Text).evaluate()) {
              final rect = tester.getRect(find.byWidget(text.widget));
              final reason =
                  '$language premium=$premium width=$width scale=$scale';
              expect(rect.overlaps(car), isFalse, reason: reason);
              expect(
                rect.left,
                greaterThanOrEqualTo(banner.left),
                reason: reason,
              );
              expect(
                rect.right,
                lessThanOrEqualTo(banner.right),
                reason: reason,
              );
              expect(
                rect.bottom,
                lessThanOrEqualTo(banner.bottom),
                reason: reason,
              );
            }
            expect(tester.takeException(), isNull);
          }
        }
      }
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('narrow banner allows large text without overflow', (
    tester,
  ) async {
    await showBanner(tester, width: 280, textScale: 2);
    await tester.pumpAndSettle();
    expect(find.text(appL10n.premiumBannerSubtitle), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
