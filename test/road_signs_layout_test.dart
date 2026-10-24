import 'package:pdd_app/presentation/screens/games/widgets/mini_game_hud.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/models/road_signs_model.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/domain/services/road_signs_engine.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/games/road_signs/road_signs_screen.dart';
import 'package:pdd_app/presentation/screens/games/road_signs/widgets/road_signs_grid.dart';
import 'package:pdd_app/presentation/screens/games/road_signs/widgets/road_signs_modal.dart';
import 'package:pdd_app/presentation/screens/games/widgets/game_ui.dart';

void main() {
  late RoadSignQuizQuestion question;
  setUpAll(() async {
    if (const bool.fromEnvironment('PDD_CAPTURE_HUD')) {
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
    final signs = RoadSignsEngine.parseSignsJson(
      jsonDecode(
            File('assets/countries/ru/questions/signs.json').readAsStringSync(),
          )
          as Map<String, dynamic>,
    );
    final options = ['2.1', '2.4', '3.1', '5.19.1']
        .map((number) => signs.firstWhere((sign) => sign.number == number))
        .toList();
    question = RoadSignQuizQuestion(
      id: 'layout',
      correctSign: options.first,
      options: options,
      correctAnswerIndex: 0,
      prompt:
          'Какой из этих знаков даёт право преимущественного проезда нерегулируемых перекрёстков?',
      officialRuleQuote: options.first.description,
      type: RoadSignQuizType.meaningDefinition,
    );
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectsService.instance.setEnabled(false);
    updateAppLocale(const Locale('ru'));
  });
  tearDown(() => updateAppLocale(const Locale('ru')));

  Widget app(
    Widget child, {
    bool dark = false,
    double scale = 1,
    String locale = 'ru',
  }) {
    updateAppLocale(Locale(locale));
    return ProviderScope(
      child: MaterialApp(
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('screen-preview'),
          child: child,
        ),
      ),
    );
  }

  void viewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('PDD_CAPTURE_HUD')) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('screen-preview')),
      );
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('output/hud-update').create(recursive: true);
      await File(
        'output/hud-update/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  final first = find.byKey(const ValueKey('road-sign-option-0'));

  for (final locale in ['ru', 'en', 'kk']) {
    for (final size in [
      const Size(320, 568),
      const Size(568, 320),
      const Size(768, 1024),
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('$locale $size text $scale: all choices remain reachable', (
          tester,
        ) async {
          viewport(tester, size);
          await tester.pumpWidget(
            app(
              RoadSignsScreen(initialDeck: [question], initialSeconds: 600),
              dark: scale == 2,
              scale: scale,
              locale: locale,
            ),
          );
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull);
          final prompt = tester.widget<Text>(find.text(question.prompt));
          expect(
            prompt.maxLines,
            isNull,
            reason: 'Never truncate the question',
          );
          for (var i = 0; i < 4; i++) {
            final option = find.byKey(ValueKey('road-sign-option-$i'));
            await tester.ensureVisible(option);
            await tester.pump();
            expect(option.hitTestable(), findsOneWidget);
            expect(
              tester.getSize(option).shortestSide,
              greaterThanOrEqualTo(100),
            );
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  testWidgets('Correct, wrong and combo feedback never move the choices', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      app(RoadSignsScreen(initialDeck: List.filled(5, question))),
    );
    await tester.pump();
    expect(find.text(appL10n.roadSignsChooseHint), findsNothing);
    expect(find.text(appL10n.roadSignsQuestionNumber(1)), findsNothing);
    expect(find.byType(MiniGameHud), findsOneWidget);
    await capture(tester, 'road-signs-new');
    final initial = tester.getRect(first);
    for (var i = 0; i < 3; i++) {
      await tester.tap(first);
      await tester.pump();
      expect(tester.getRect(first), initial);
      await tester.pump(const Duration(milliseconds: 450));
      expect(tester.getRect(first), initial);
    }
    await tester.tap(find.byKey(const ValueKey('road-sign-option-1')));
    await tester.pump();
    expect(tester.getRect(first), initial);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNWidgets(2));
    expect(find.byType(GameLifeLossBadge), findsOneWidget);
    await capture(tester, 'road-signs-error');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Accessible options expose tap actions, not answer names', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(app(RoadSignsScreen(initialDeck: [question])));
    await tester.pump();
    final node = tester.getSemantics(first);
    expect(node.label, appL10n.roadSignsOption(1));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(find.bySemanticsLabel(question.correctSign.title), findsNothing);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pump();
    expect(find.text(appL10n.roadSignsCorrectPoints(12)), findsOneWidget);
    expect(
      tester
          .getSemantics(first)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    semantics.dispose();
  });

  testWidgets('Accepted answer stays visible when the timer expires', (
    tester,
  ) async {
    viewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      app(RoadSignsScreen(initialDeck: [question], initialSeconds: 1)),
    );
    await tester.pump(const Duration(milliseconds: 900));
    await tester.tap(first);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(RoadSignsGrid), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(GameResultOverlay), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final locale in ['ru', 'en', 'kk']) {
    testWidgets(
      '$locale: explanation scrolls while Continue remains reachable',
      (tester) async {
        viewport(tester, const Size(320, 568));
        var continued = 0;
        await tester.pumpWidget(
          app(
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => RoadSignsModal.show(
                    context,
                    result: RoadSignAnswerResult(
                      question: question,
                      selectedIndex: 1,
                      isCorrect: false,
                    ),
                    onContinue: () => continued++,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
            dark: true,
            scale: 2,
            locale: locale,
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(appL10n.continueButton).hitTestable(), findsOneWidget);
        await tester.tap(find.text(appL10n.continueButton));
        await tester.pumpAndSettle();
        expect(continued, 1);
      },
    );
  }
}
