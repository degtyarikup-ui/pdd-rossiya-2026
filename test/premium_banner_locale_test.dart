import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/premium_banner_card.dart';

void main() {
  testWidgets('retained premium banner updates immediately for ru, en and kk', (
    tester,
  ) async {
    final locale = ValueNotifier(const Locale('ru'));
    addTearDown(() {
      locale.dispose();
      updateAppLocale(const Locale('ru'));
    });
    updateAppLocale(locale.value);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isPremiumProvider.overrideWithValue(false),
          dailyCardsRemainingProvider.overrideWithValue(5),
          dailyFreeLimitProvider.overrideWithValue(5),
        ],
        child: ValueListenableBuilder<Locale>(
          valueListenable: locale,
          builder: (context, selected, child) => MaterialApp(
            locale: selected,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: const Scaffold(body: PremiumBannerCard()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(appL10n.premiumAccessTitle), findsOneWidget);

    for (final language in ['en', 'kk', 'ru']) {
      final previousTitle = appL10n.premiumAccessTitle;
      updateAppLocale(Locale(language));
      locale.value = Locale(language);
      await tester.pumpAndSettle();
      expect(find.text(appL10n.premiumAccessTitle), findsOneWidget);
      expect(find.text(appL10n.premiumBannerSubtitle), findsOneWidget);
      expect(find.text(previousTitle), findsNothing);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
