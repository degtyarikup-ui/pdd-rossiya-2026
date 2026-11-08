import 'helpers/achievement_awards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/models/road_signs_model.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/games/road_signs/road_signs_screen.dart';
import 'package:pdd_app/presentation/screens/games/road_signs/widgets/road_signs_grid.dart';
import 'package:pdd_app/presentation/screens/games/road_signs/widgets/road_signs_modal.dart';
import 'package:pdd_app/presentation/screens/games/widgets/game_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sign1 = SignItem(
    number: '1.1',
    title: 'Железнодорожный переезд со шлагбаумом',
    image: 'crossing_barrier.svg',
    category: 'Предупреждающие знаки',
    description: 'О приближении к ж/д переезду со шлагбаумом.',
    folkName: 'Заборчик',
  );

  const sign2 = SignItem(
    number: '2.1',
    title: 'Главная дорога',
    image: 'priority.svg',
    category: 'Знаки приоритета',
    description: 'Предоставлено право преимущественного проезда.',
    folkName: 'Главная',
  );

  const sign3 = SignItem(
    number: '3.1',
    title: 'Въезд запрещен',
    image: 'brick.svg',
    category: 'Запрещающие знаки',
    description: 'Запрещается въезд всех транспортных средств.',
    folkName: 'Кирпич',
  );

  const sign4 = SignItem(
    number: '4.1.1',
    title: 'Движение прямо',
    image: 'straight.svg',
    category: 'Предписывающие знаки',
    description: 'Разрешается движение только прямо.',
    folkName: 'Стрелка прямо',
  );

  RoadSignQuizQuestion makeQuestion(String id, int correctIdx) {
    final list = [sign1, sign2, sign3, sign4];
    return RoadSignQuizQuestion(
      id: id,
      correctSign: list[correctIdx],
      options: list,
      correctAnswerIndex: correctIdx,
      prompt: 'Вопрос для знака ${list[correctIdx].number}',
      officialRuleQuote: list[correctIdx].description,
      type: RoadSignQuizType.titleMatch,
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectsService.instance.setEnabled(false);
  });

  Widget buildTestApp(Widget child) {
    return ProviderScope(
      overrides: [noAchievementAwards],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }

  void setupViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('Adversarial Stress Test: Modal answer feedback for every choice', () {
    for (int correctIdx = 0; correctIdx < 4; correctIdx++) {
      for (int chosenIdx = 0; chosenIdx < 4; chosenIdx++) {
        final isCorrect = correctIdx == chosenIdx;
        testWidgets('Permutation: correct=$correctIdx, chosen=$chosenIdx', (
          tester,
        ) async {
          setupViewport(tester);
          final q = makeQuestion('perm_${correctIdx}_$chosenIdx', correctIdx);
          final res = RoadSignAnswerResult(
            question: q,
            selectedIndex: chosenIdx,
            isCorrect: isCorrect,
          );

          await tester.pumpWidget(
            buildTestApp(
              Scaffold(
                body: RoadSignsModal(result: res, onContinue: () {}),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          for (var i = 0; i < 4; i++) {
            final card = tester.widget<Container>(
              find.byKey(ValueKey('road-sign-review-$i')),
            );
            final decoration = card.decoration as BoxDecoration;
            expect(decoration.border, isNull);
            expect(decoration.boxShadow, isNull);
            expect(
              decoration.color,
              i == correctIdx
                  ? AppThemeColors.light.greenLight
                  : !isCorrect && i == chosenIdx
                  ? AppThemeColors.light.redLight
                  : AppThemeColors.light.background,
            );
            final icons = find.descendant(
              of: find.byKey(ValueKey('road-sign-review-$i')),
              matching: find.byType(Icon),
            );
            expect(
              icons,
              i == correctIdx || (!isCorrect && i == chosenIdx)
                  ? findsOneWidget
                  : findsNothing,
            );
          }
        });
      }
    }
  });

  group('Adversarial Stress Test: Re-entrancy, Rapid Multi-Tap & Concurrency', () {
    testWidgets(
      'Spam-tapping multiple cards in rapid succession triggers only 1 answer',
      (tester) async {
        setupViewport(tester);
        final q1 = makeQuestion('q1', 0);
        final q2 = makeQuestion('q2', 1);

        await tester.pumpWidget(
          buildTestApp(RoadSignsScreen(initialDeck: [q1, q2], initialLives: 5)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final cards = find.descendant(
          of: find.byType(RoadSignsGrid),
          matching: find.byType(InkWell),
        );
        expect(cards, findsNWidgets(4));

        // Rapidly tap all 4 cards without pumping in between
        await tester.tap(cards.at(0), warnIfMissed: false);
        await tester.tap(cards.at(1), warnIfMissed: false);
        await tester.tap(cards.at(2), warnIfMissed: false);
        await tester.tap(cards.at(3), warnIfMissed: false);

        await tester.pump();

        // In blitz mode, no blocking modal appears
        expect(find.byType(RoadSignsModal), findsNothing);

        // Score should only reflect the first tap (correct, +12)
        expect(find.text('12'), findsOneWidget);

        // Lives should still be 5 because the first tap was correct and subsequent taps were blocked
        final livesWidget = tester.widget<GameLives>(find.byType(GameLives));
        expect(livesWidget.lives, 5);

        // After 450ms highlight, advances to question 2
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pump();
        expect(find.text(q2.prompt), findsOneWidget);
      },
    );
  });

  group(
    'Adversarial Stress Test: Complete 5-Life Depletion Sequence in Blitz',
    () {
      testWidgets(
        'Losing all 5 lives in sequence ends on 5th error and allows full mistake review',
        (tester) async {
          setupViewport(tester);
          final deck = List.generate(6, (i) => makeQuestion('deck_$i', 0));

          await tester.pumpWidget(
            buildTestApp(RoadSignsScreen(initialDeck: deck, initialLives: 5)),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          for (int step = 1; step <= 5; step++) {
            final cards = find.descendant(
              of: find.byType(RoadSignsGrid),
              matching: find.byType(InkWell),
            );
            // Tap wrong card (index 1, correct is 0)
            await tester.tap(cards.at(1));
            await tester.pump();

            // Error highlight delay (800ms)
            await tester.pump(const Duration(milliseconds: 800));
            await tester.pump();

            if (step < 5) {
              // Still playing
              expect(find.byType(RoadSignsGrid), findsOneWidget);
              final lives = tester.widget<GameLives>(find.byType(GameLives));
              expect(lives.lives, 5 - step);
            } else {
              // Step 5: Game Over!
              await tester.pump();
              expect(find.byType(GameResultOverlay), findsOneWidget);
              expect(find.byType(RoadSignsGrid), findsNothing);
            }
          }

          // Verify mistake button opens mistake sheet with 5 mistakes
          expect(find.textContaining('5'), findsWidgets);
          await tester.tap(find.text(appL10n.gameRunMistakesButton(5)));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.text(appL10n.gameMistakesReview), findsOneWidget);

          // Tapping a mistake opens RoadSignsModal with official rules details
          final mistakeTile = find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(InkWell),
              )
              .first;
          await tester.tap(mistakeTile);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(RoadSignsModal), findsOneWidget);
        },
      );
    },
  );

  group('Adversarial Stress Test: Continuous Blitz Timer', () {
    testWidgets(
      'Timer counts down continuously across questions in blitz mode',
      (tester) async {
        setupViewport(tester);
        final q1 = makeQuestion('q1', 0);
        final q2 = makeQuestion('q2', 1);

        await tester.pumpWidget(
          buildTestApp(
            RoadSignsScreen(initialDeck: [q1, q2], initialSeconds: 20),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Let 3 seconds pass in game
        await tester.pump(const Duration(seconds: 3));
        var timeBar = tester.widget<GameTimeBar>(find.byType(GameTimeBar));
        expect(timeBar.secondsLeft, 17);

        // Tap card 0 (correct answer)
        final cards = find.descendant(
          of: find.byType(RoadSignsGrid),
          matching: find.byType(InkWell),
        );
        await tester.tap(cards.at(0));
        await tester.pump();

        // Advance 450ms highlight delay
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pump();

        // Advanced to question 2
        expect(find.text(q2.prompt), findsOneWidget);

        // Advance 17 seconds to trigger legitimate time up
        await tester.pump(const Duration(seconds: 17));
        await tester.pump(const Duration(milliseconds: 500));

        await tester.pump();
        expect(find.byType(GameResultOverlay), findsOneWidget);
        expect(find.text(appL10n.gameTimeUp), findsOneWidget);
      },
    );
  });

  group('Adversarial Stress Test: Round Restart & State Reset', () {
    testWidgets(
      'Restarting round from GameResultOverlay resets timer, lives, score, and combo',
      (tester) async {
        setupViewport(tester);
        final q1 = makeQuestion('q1', 0);
        final q2 = makeQuestion('q2', 1);

        await tester.pumpWidget(
          buildTestApp(
            RoadSignsScreen(
              initialDeck: [q1, q2],
              initialSeconds: 5,
              initialLives: 1,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Answer wrong to lose life
        final cards = find.descendant(
          of: find.byType(RoadSignsGrid),
          matching: find.byType(InkWell),
        );
        await tester.tap(cards.at(1));
        await tester.pump();

        // Wait 800ms error delay
        await tester.pump(const Duration(milliseconds: 800));
        await tester.pump(const Duration(milliseconds: 300));

        await tester.pump();
        expect(find.byType(GameResultOverlay), findsOneWidget);

        // Tap restart button in overlay
        await tester.tap(find.text(appL10n.gameRestart));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Should be back to game screen immediately without waiting 1 full second for timer tick
        expect(
          find.byType(GameResultOverlay),
          findsNothing,
          reason:
              'GameResultOverlay must be dismissed immediately on restart without a 1-second lag',
        );
        expect(find.byType(RoadSignsGrid), findsOneWidget);

        // Lives reset to initialLives (1)
        final lives = tester.widget<GameLives>(find.byType(GameLives));
        expect(lives.lives, 1);

        // Score reset to 0
        expect(find.text('0'), findsOneWidget);

        // Time reset to 5
        final timeBar = tester.widget<GameTimeBar>(find.byType(GameTimeBar));
        expect(timeBar.secondsLeft, 5);
      },
    );
  });
}
