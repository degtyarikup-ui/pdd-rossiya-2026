import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/premium_celebration_screen.dart';

// Optional visual review output:
// flutter test test/premium_celebration_screen_test.dart --dart-define=PREMIUM_CAPTURE=true
const _capture = bool.fromEnvironment('PREMIUM_CAPTURE');
const _boundary = ValueKey('premium-celebration-boundary');

void main() {
  // Как в main(): данные дат для языков приложения загружаются до первого показа.
  setUpAll(initAppDateFormatting);
  setUp(() => SoundEffectsService.instance.setEnabled(false));
  tearDown(() {
    SoundEffectsService.instance.setEnabled(true);
    updateAppLocale(const Locale('ru'));
  });

  Future<void> open(
    WidgetTester tester, {
    required PremiumCelebrationReason reason,
    DateTime? expiresAt,
    String? message,
    String language = 'ru',
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(780, 1688);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    updateAppLocale(Locale(language));
    await tester.pumpWidget(
      RepaintBoundary(
        key: _boundary,
        child: MaterialApp(
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => PremiumCelebrationScreen.show(
                  context,
                  reason: reason,
                  expiresAt: expiresAt,
                  message: message,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!_capture) return;
    await tester.runAsync(() async {
      final boundary =
          tester.renderObject(find.byKey(_boundary)) as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('output/premium_celebration/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('a purchase shows the green screen with access date and perks', (
    tester,
  ) async {
    await open(
      tester,
      reason: PremiumCelebrationReason.purchased,
      expiresAt: DateTime(2026, 11, 4, 12),
    );

    expect(find.text('Премиум открыт!'), findsOneWidget);
    expect(
      find.text('Спасибо за поддержку! Все возможности уже открыты.'),
      findsOneWidget,
    );
    expect(find.text('Доступ до 4 ноября 2026'), findsOneWidget);
    expect(find.byType(PremiumSeal), findsOneWidget);
    expect(
      find.textContaining(appL10n.premiumBenefitAiTitle, findRichText: true),
      findsOneWidget,
    );
    final scaffold = tester.widget<Scaffold>(
      find
          .descendant(
            of: find.byType(PremiumCelebrationScreen),
            matching: find.byType(Scaffold),
          )
          .first,
    );
    expect(scaffold.backgroundColor, AppColors.green);
    await capture(tester, 'purchased_ru');

    await tester.tap(find.text('Отлично!'));
    await tester.pumpAndSettle();
    expect(find.byType(PremiumCelebrationScreen), findsNothing);
  });

  testWidgets('a manual grant uses the same screen with the admin note', (
    tester,
  ) async {
    await open(
      tester,
      reason: PremiumCelebrationReason.granted,
      expiresAt: DateTime(2026, 10, 31, 12),
      message: 'Подарок)',
    );

    expect(find.text('Вам выдан Премиум!'), findsOneWidget);
    expect(find.text('Подарок)'), findsOneWidget);
    expect(find.text('Доступ до 31 октября 2026'), findsOneWidget);
    await capture(tester, 'granted_ru');

    await tester.tap(find.byTooltip(appL10n.close));
    await tester.pumpAndSettle();
    expect(find.byType(PremiumCelebrationScreen), findsNothing);
  });

  testWidgets('lifetime access and other languages fit the screen', (
    tester,
  ) async {
    for (final language in ['en', 'kk']) {
      await open(
        tester,
        reason: PremiumCelebrationReason.granted,
        language: language,
      );
      expect(find.text(appL10n.premiumCelebrationLifetime), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, 'lifetime_$language');
      await tester.tap(find.text(appL10n.premiumCelebrationAction));
      await tester.pumpAndSettle();
    }
  });
}
