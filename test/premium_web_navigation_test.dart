import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/premium_benefits_screen.dart';

void main() {
  for (final window in [
    const Size(1754, 1290),
    const Size(1440, 900),
    const Size(390, 844),
  ]) {
    for (final escape in [false, true]) {
      testWidgets(
        'premium can close in a constrained viewport $window escape=$escape',
        (tester) async {
          tester.view.physicalSize = window;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              locale: const Locale('ru'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              // Reproduce the old web shell: a narrow Navigator inherits the full
              // browser MediaQuery, as in the user's screenshot.
              builder: (_, child) => Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: child,
                ),
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PremiumBenefitsScreen(),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          final close = find.byKey(const ValueKey('premium-close-benefits'));
          expect(
            close.hitTestable(),
            findsOneWidget,
            reason: 'Close must use the page width, not the browser width',
          );
          if (escape) {
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          } else {
            await tester.tap(close);
          }
          await tester.pumpAndSettle();
          expect(find.byType(PremiumBenefitsScreen), findsNothing);
          expect(find.text('open'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
