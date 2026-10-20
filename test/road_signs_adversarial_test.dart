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

  group('Adversarial Stress Test: Modal Dialog Border and Styling Integrity', () {
    for (int correctIdx = 0; correctIdx < 4; correctIdx++) {
      for (int chosenIdx = 0; chosenIdx < 4; chosenIdx++) {
        final isCorrect = correctIdx == chosenIdx;
        testWidgets('Permutation: correct=$correctIdx, chosen=$chosenIdx', (tester) async {
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
                body: RoadSignsModal(
                  result: res,
                  onContinue: () {},
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          // Find the 4 mini cards inside the Row of options
          // In RoadSignsModal, the Row of options has 4 Expanded widgets
          final miniCardContainers = tester.widgetList<Container>(
            find.descendant(
              of: find.byType(Row),
              matching: find.byType(Container),
            ),
          ).where((c) {
            // Mini card has height 60
            return (c.constraints?.maxHeight == 60 || c.constraints?.minHeight == 60) ||
                   (c.decoration is BoxDecoration && (c.decoration as BoxDecoration).borderRadius == BorderRadius.circular(10));
          }).toList();

          expect(miniCardContainers.length, 4, reason: 'Must have exactly 4 mini-sign option cards');

          for (int i = 0; i < 4; i++) {
            final boxDec = miniCardContainers[i].decoration as BoxDecoration;
            final border = boxDec.border!;
            if (i == correctIdx) {
              expect(border.top.color, AppThemeColors.light.green,
                  reason: 'Option $i (correct) must have green border');
              expect(border.top.width, 2.0);
              expect(boxDec.color, AppThemeColors.light.greenLight);
            } else if (!isCorrect && i == chosenIdx) {
              expect(border.top.color, AppThemeColors.light.red,
                  reason: 'Option $i (chosen wrong) must have red border');
              expect(border.top.width, 2.0);
              expect(boxDec.color, AppThemeColors.light.redLight);
            } else {
              expect(border.top.color, AppThemeColors.light.divider.withValues(alpha: 0.4),
                  reason: 'Neutral option $i must have subtle divider border');
              expect(border.top.width, 1.0);
              expect(boxDec.color, AppThemeColors.light.gray);
            }
          }
        });
      }
    }
  });

  group('Adversarial Stress Test: Re-entrancy, Rapid Multi-Tap & Concurrency', () {
    testWidgets('Spam-tapping multiple cards in rapid succession triggers only 1 answer', (tester) async {
      setupViewport(tester);
      final q1 = makeQuestion('q1', 0);
      final q2 = makeQuestion('q2', 1);

      await tester.pumpWidget(
        buildTestApp(
          RoadSignsScreen(
            initialDeck: [q1, q2],
            initialLives: 5,
          ),
        ),
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
      await tester.pump(const Duration(milliseconds: 300));

      // Exactly one modal should open
      expect(find.byType(RoadSignsModal), findsOneWidget);

      // Score should only reflect the first tap (correct, +12)
      expect(find.text('12'), findsOneWidget);

      // Lives should still be 5 because the first tap was correct and subsequent taps were blocked
      final livesWidget = tester.widget<GameLives>(find.byType(GameLives));
      expect(livesWidget.lives, 5);
    });
  });

  group('Adversarial Stress Test: Barrier Tap & Android Back Button Dismissal', () {
    testWidgets('Barrier tap dismisses modal, triggers single continue, and resumes timer', (tester) async {
      setupViewport(tester);
      final q1 = makeQuestion('q1', 0);
      final q2 = makeQuestion('q2', 1);

      await tester.pumpWidget(
        buildTestApp(
          RoadSignsScreen(
            initialDeck: [q1, q2],
            initialSeconds: 30,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap card 0
      final cards = find.descendant(
        of: find.byType(RoadSignsGrid),
        matching: find.byType(InkWell),
      );
      await tester.tap(cards.at(0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(RoadSignsModal), findsOneWidget);

      // Tap outside dialog at top-left edge (barrier tap)
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Modal should be dismissed
      expect(find.byType(RoadSignsModal), findsNothing);

      // Should advance to question 2
      expect(find.text(q2.prompt), findsOneWidget);

      // Advance 2 seconds to verify timer resumed
      await tester.pump(const Duration(seconds: 2));
      final timeBar = tester.widget<GameTimeBar>(find.byType(GameTimeBar));
      expect(timeBar.secondsLeft, 28);
    });

    testWidgets('Barrier tap when 0 lives triggers GameResultOverlay, not next question', (tester) async {
      setupViewport(tester);
      final q1 = makeQuestion('q1', 0);
      final q2 = makeQuestion('q2', 1);

      await tester.pumpWidget(
        buildTestApp(
          RoadSignsScreen(
            initialDeck: [q1, q2],
            initialLives: 1, // Only 1 life!
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap wrong card (card 1)
      final cards = find.descendant(
        of: find.byType(RoadSignsGrid),
        matching: find.byType(InkWell),
      );
      await tester.tap(cards.at(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(RoadSignsModal), findsOneWidget);

      // Dismiss via barrier tap
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // GameResultOverlay is shown
      expect(find.byType(GameResultOverlay), findsOneWidget);
      expect(find.byType(RoadSignsGrid), findsNothing);
    });
  });

  group('Adversarial Stress Test: Complete 5-Life Depletion Sequence', () {
    testWidgets('Losing all 5 lives in sequence shows modal each time, ends on 5th continue', (tester) async {
      setupViewport(tester);
      final deck = List.generate(6, (i) => makeQuestion('deck_$i', 0));

      await tester.pumpWidget(
        buildTestApp(
          RoadSignsScreen(
            initialDeck: deck,
            initialLives: 5,
          ),
        ),
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
        await tester.pump(const Duration(milliseconds: 300));

        // Modal should be open
        expect(find.byType(RoadSignsModal), findsOneWidget);

        // Tap Continue
        await tester.tap(find.text('Продолжить'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        if (step < 5) {
          // Still playing
          expect(find.byType(RoadSignsGrid), findsOneWidget);
          final lives = tester.widget<GameLives>(find.byType(GameLives));
          expect(lives.lives, 5 - step);
        } else {
          // Step 5: Game Over!
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
    });
  });

  group('Adversarial Stress Test: Timer Freezing and Resuming Rigor', () {
    testWidgets('Timer stays perfectly frozen for 15 virtual seconds while modal is open', (tester) async {
      setupViewport(tester);
      final q1 = makeQuestion('q1', 0);
      final q2 = makeQuestion('q2', 1);

      await tester.pumpWidget(
        buildTestApp(
          RoadSignsScreen(
            initialDeck: [q1, q2],
            initialSeconds: 20,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Let 3 seconds pass in game
      await tester.pump(const Duration(seconds: 3));
      var timeBar = tester.widget<GameTimeBar>(find.byType(GameTimeBar));
      expect(timeBar.secondsLeft, 17);

      // Open modal
      final cards = find.descendant(
        of: find.byType(RoadSignsGrid),
        matching: find.byType(InkWell),
      );
      await tester.tap(cards.at(0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Advance 15 seconds! (If timer wasn't frozen, 17 - 15 = 2, almost time up)
      await tester.pump(const Duration(seconds: 15));

      // Modal is STILL open, no time up
      expect(find.byType(RoadSignsModal), findsOneWidget);
      expect(find.byType(GameResultOverlay), findsNothing);

      // Dismiss modal
      await tester.tap(find.text('Продолжить'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Check secondsLeft: must STILL be 17!
      timeBar = tester.widget<GameTimeBar>(find.byType(GameTimeBar));
      expect(timeBar.secondsLeft, 17);

      // Now advance 17 seconds to trigger legitimate time up
      await tester.pump(const Duration(seconds: 17));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(GameResultOverlay), findsOneWidget);
      expect(find.text(appL10n.gameTimeUp), findsOneWidget);
    });
  });

  group('Adversarial Stress Test: Round Restart & State Reset', () {
    testWidgets('Restarting round from GameResultOverlay resets timer, lives, score, and combo', (tester) async {
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
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Продолжить'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(GameResultOverlay), findsOneWidget);

      // Tap restart button in overlay
      await tester.tap(find.text(appL10n.gameRestart));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Should be back to game screen immediately without waiting 1 full second for timer tick
      expect(find.byType(GameResultOverlay), findsNothing,
          reason: 'GameResultOverlay must be dismissed immediately on restart without a 1-second lag');
      expect(find.byType(RoadSignsGrid), findsOneWidget);

      // Lives reset to initialLives (1)
      final lives = tester.widget<GameLives>(find.byType(GameLives));
      expect(lives.lives, 1);

      // Score reset to 0
      expect(find.text('0'), findsOneWidget);

      // Time reset to 5
      final timeBar = tester.widget<GameTimeBar>(find.byType(GameTimeBar));
      expect(timeBar.secondsLeft, 5);
    });
  });
}
