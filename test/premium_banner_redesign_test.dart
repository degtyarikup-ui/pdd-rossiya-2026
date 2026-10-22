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
  }) => tester.pumpWidget(
    ProviderScope(
      overrides: [
        isPremiumProvider.overrideWithValue(premium),
        dailyCardsRemainingProvider.overrideWithValue(remaining),
        dailyFreeLimitProvider.overrideWithValue(5),
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
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
