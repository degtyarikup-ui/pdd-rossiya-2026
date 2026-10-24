import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/home/home_screen.dart';
import 'package:pdd_app/presentation/screens/training/marathon_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const capture = bool.fromEnvironment('PDD_CAPTURE_MARATHON');
  setUpAll(() async {
    // Use the shipped font for layout assertions as well as exported previews.
    // Ahem's square glyphs distort the existing exam badges at large text sizes.
    {
      final fonts = FontLoader(AppTheme.fontFamily);
      for (final weight in [
        'Regular',
        'Medium',
        'SemiBold',
        'Bold',
        'ExtraBold',
      ]) {
        fonts.addFont(rootBundle.load('assets/fonts/Onest-$weight.ttf'));
      }
      await fonts.load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });

  Future<void> screenshot(
    WidgetTester tester,
    GlobalKey key,
    String name,
  ) async {
    if (!capture) return;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('output/marathon-preview/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final config in [
    (
      name: 'phone',
      size: const Size(390, 844),
      scale: 1.0,
      lang: 'ru',
      dark: false,
    ),
    (
      name: 'compact-large-text',
      size: const Size(320, 568),
      scale: 2.0,
      lang: 'kk',
      dark: false,
    ),
    (
      name: 'landscape',
      size: const Size(844, 390),
      scale: 1.0,
      lang: 'en',
      dark: false,
    ),
    (
      name: 'dark',
      size: const Size(414, 896),
      scale: 1.0,
      lang: 'ru',
      dark: true,
    ),
  ]) {
    testWidgets('home cards and resume actions fit ${config.name}', (
      tester,
    ) async {
      updateAppLocale(Locale(config.lang));
      addTearDown(() => updateAppLocale(const Locale('ru')));
      tester.view.physicalSize = config.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'notification_prompt_shown': true,
        'home_exam_concept_index': 1,
      });
      final source = ProgressDataSource();
      await source.init();
      final key = GlobalKey();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            progressDataSourceProvider.overrideWithValue(source),
            isAuthenticatedProvider.overrideWithValue(false),
            currentUserProvider.overrideWithValue(null),
            statsProvider.overrideWith(
              (_) async => {
                'correctAnswers': 138,
                'answeredQuestions': 252,
                'wrongQuestions': 114,
                'passedTickets': 1,
                'totalQuestions': 800,
                'totalTickets': 40,
              },
            ),
            unfinishedSessionProvider.overrideWith((_) async => null),
          ],
          child: MaterialApp(
            navigatorKey: navigator,
            debugShowCheckedModeBanner: false,
            theme: config.dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            locale: Locale(config.lang),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(config.scale),
                padding: const EdgeInsets.only(top: 44, bottom: 24),
              ),
              child: RepaintBoundary(key: key, child: child!),
            ),
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (capture) {
        final imageContext = tester.element(find.byType(HomeScreen));
        await tester.runAsync(() async {
          for (final name in ['topics', 'tickets', 'errors', 'favorites']) {
            await precacheImage(
              AssetImage('assets/images/home_icon_$name.png'),
              imageContext,
            );
          }
        });
        await tester.pumpAndSettle();
      }
      final context = tester.element(find.byType(HomeScreen));
      final l10n = AppLocalizations.of(context);
      expect(find.text(l10n.rateUs), findsOneWidget);
      expect(find.text(l10n.marathon), findsOneWidget);
      final ratePosition = tester.getBottomLeft(find.text(l10n.rateUs));
      final marathonPosition = tester.getBottomLeft(find.text(l10n.marathon));
      expect(ratePosition.dy, closeTo(marathonPosition.dy, 0.1));
      expect(ratePosition.dx, lessThan(marathonPosition.dx));
      await screenshot(tester, key, 'home-${config.name}');
      await tester.ensureVisible(find.text(l10n.marathon));
      await tester.pumpAndSettle();
      expect(find.text(l10n.marathon).hitTestable(), findsOneWidget);
      expect(find.text(l10n.rateUs).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);

      final dialog = showDialog<bool>(
        context: context,
        builder: (_) => const MarathonResumeDialog(answered: 137, total: 800),
      );
      await tester.pumpAndSettle();
      final primary = find.widgetWithText(ElevatedButton, l10n.continueButton);
      await tester.ensureVisible(primary);
      await tester.pumpAndSettle();
      expect(primary.hitTestable(), findsOneWidget);
      final style = Theme.of(
        tester.element(primary),
      ).elevatedButtonTheme.style!;
      expect(style.backgroundColor!.resolve({}), AppColors.of(context).accent);
      await screenshot(tester, key, 'resume-${config.name}');
      await tester.ensureVisible(find.text(l10n.marathonRestart));
      await tester.pumpAndSettle();
      expect(find.text(l10n.marathonRestart).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      navigator.currentState!.pop();
      await dialog;
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
