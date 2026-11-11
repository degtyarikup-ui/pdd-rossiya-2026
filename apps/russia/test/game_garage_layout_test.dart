import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/services/game_garage_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_garage.dart';

void main() {
  setUpAll(() async {
    final fonts = FontLoader(AppTheme.fontFamily);
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      fonts.addFont(rootBundle.load('assets/fonts/Onest-$weight.ttf'));
    }
    await fonts.load();
  });
  tearDown(() => updateAppLocale(const Locale('ru')));

  for (final locale in ['ru', 'en', 'kk']) {
    testWidgets(
      'garage catalogue and car fit small accessible $locale screens',
      (tester) async {
        for (final size in [const Size(320, 480), const Size(568, 320)]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          updateAppLocale(Locale(locale));
          await tester.pumpWidget(
            MaterialApp(
              key: UniqueKey(),
              theme: AppTheme.lightTheme,
              locale: Locale(locale),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: GameGarage(
                selected: GameGarageService.starter,
                models: GameGarageService.vehicleIds,
                paints: GameGarageService.allPaints,
                correctTotal: 350,
                mileageMm: const {},
                onSelect: (_) async => true,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$size catalogue');
          await tester.tap(find.byKey(const ValueKey('garage-car-hatch')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$size detail');
          expect(
            find.text(appL10n.gamesGarageSave).hitTestable(),
            findsOneWidget,
          );
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );
  }
}
