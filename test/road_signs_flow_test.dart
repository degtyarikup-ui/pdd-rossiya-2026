import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/models/road_signs_model.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/games/road_signs/road_signs_screen.dart';
import 'package:pdd_app/presentation/screens/games/road_signs/widgets/road_signs_grid.dart';
import 'package:pdd_app/presentation/screens/games/road_signs/widgets/road_signs_modal.dart';
import 'package:pdd_app/presentation/screens/games/widgets/game_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sign21 = SignItem(
    number: '2.1',
    title: 'Главная дорога',
    image: 'priority.svg',
    category: 'Знаки приоритета',
    description: 'Дорога, на которой предоставлено право преимущественного проезда.',
    folkName: 'Главная',
  );

  const sign24 = SignItem(
    number: '2.4',
    title: 'Уступите дорогу',
    image: 'yield.svg',
    category: 'Знаки приоритета',
    description: 'Водитель должен уступить дорогу приближающимся ТС.',
    folkName: 'Уступи дорогу',
  );

  const sign31 = SignItem(
    number: '3.1',
    title: 'Въезд запрещен',
    image: 'brick.svg',
    category: 'Запрещающие знаки',
    description: 'Запрещается въезд всех транспортных средств в данном направлении.',
    folkName: 'Кирпич',
  );

  const sign519 = SignItem(
    number: '5.19.1',
    title: 'Пешеходный переход',
    image: 'crosswalk.svg',
    category: 'Знаки особых предписаний',
    description: 'Обозначает место пешеходного перехода через проезжую часть.',
    folkName: 'Зебра',
  );

  final testQuestion1 = RoadSignQuizQuestion(
    id: 'q1',
    correctSign: sign21,
    options: const [sign21, sign24, sign31, sign519],
    correctAnswerIndex: 0,
    prompt: 'Какой из этих знаков даёт право преимущественного проезда?',
    officialRuleQuote: 'Дорога, на которой предоставлено право преимущественного проезда.',
    type: RoadSignQuizType.meaningDefinition,
  );

  final testQuestion2 = RoadSignQuizQuestion(
    id: 'q2',
    correctSign: sign31,
    options: const [sign24, sign31, sign21, sign519],
    correctAnswerIndex: 1,
    prompt: 'Какой знак в народе называют «Кирпич»?',
    officialRuleQuote: 'Запрещается въезд всех транспортных средств.',
    type: RoadSignQuizType.folkNameMatch,
  );

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
    tester.view.physicalSize = const Size(400, 920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('RoadSignsModal Unit/Widget Tests', () {
    testWidgets('Displays correct answer details with green styling', (tester) async {
      setupViewport(tester);
      bool continued = false;
      final result = RoadSignAnswerResult(
        question: testQuestion1,
        selectedIndex: 0,
        isCorrect: true,
      );

      await tester.pumpWidget(
        buildTestApp(
          Scaffold(
            body: RoadSignsModal(
              result: result,
              onContinue: () => continued = true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Header and Prompt
      expect(find.text('Детали ответа'), findsOneWidget);
      expect(find.text(testQuestion1.prompt), findsOneWidget);

      // Status pill
      expect(find.text('✓ Ваш ответ верный'), findsOneWidget);
      expect(find.text('✕ Ваш ответ неверный'), findsNothing);

      // No wrong choice card
      expect(find.textContaining('Ваш выбор:'), findsNothing);

      // Correct answer card
      expect(find.text('Правильный ответ:'), findsOneWidget);
      expect(find.text('2.1 «Главная дорога»'), findsOneWidget);
      expect(find.text(testQuestion1.officialRuleQuote), findsOneWidget);

      // Green border verified on correct option
      final containers = tester.widgetList<Container>(find.byType(Container));
      final hasGreenBorder = containers.any((c) {
        final dec = c.decoration;
        if (dec is BoxDecoration && dec.border != null) {
          return dec.border!.top.color == AppThemeColors.light.green;
        }
        return false;
      });
      expect(hasGreenBorder, isTrue, reason: 'Correct option must have green border');

      // Tapping "Продолжить" triggers callback
      await tester.tap(find.text('Продолжить'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(continued, isTrue);
    });

    testWidgets('Displays incorrect answer details with red choice and green correct', (tester) async {
      setupViewport(tester);
      bool continued = false;
      final result = RoadSignAnswerResult(
        question: testQuestion1,
        selectedIndex: 1, // Chose sign 2.4 instead of 2.1
        isCorrect: false,
      );

      await tester.pumpWidget(
        buildTestApp(
          Scaffold(
            body: RoadSignsModal(
              result: result,
              onContinue: () => continued = true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Status pill
      expect(find.text('✕ Ваш ответ неверный'), findsOneWidget);
      expect(find.text('✓ Ваш ответ верный'), findsNothing);

      // User choice card
      expect(find.text('✕ Ваш выбор: знак 2.4'), findsOneWidget);

      // Correct answer card
      expect(find.text('Правильный ответ:'), findsOneWidget);
      expect(find.text('2.1 «Главная дорога»'), findsOneWidget);

      // Check both red and green borders are present in the mini options strip
      final containers = tester.widgetList<Container>(find.byType(Container));
      final hasGreenBorder = containers.any((c) {
        final dec = c.decoration;
        if (dec is BoxDecoration && dec.border != null) {
          return dec.border!.top.color == AppThemeColors.light.green;
        }
        return false;
      });
      final hasRedBorder = containers.any((c) {
        final dec = c.decoration;
        if (dec is BoxDecoration && dec.border != null) {
          return dec.border!.top.color == AppThemeColors.light.red;
        }
        return false;
      });
      expect(hasGreenBorder, isTrue, reason: 'Must show green border on correct option');
      expect(hasRedBorder, isTrue, reason: 'Must show red border on chosen wrong option');

      // Close button also calls onContinue
      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(continued, isTrue);
    });

    testWidgets('Displays localized texts when locale is English', (tester) async {
      setupViewport(tester);
      updateAppLocale(const Locale('en'));
      addTearDown(() => updateAppLocale(const Locale('ru')));
      final result = RoadSignAnswerResult(
        question: testQuestion1,
        selectedIndex: 1,
        isCorrect: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: RoadSignsModal(
                result: result,
                onContinue: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Answer details'), findsOneWidget);
      expect(find.text('✕ Your answer is incorrect'), findsOneWidget);
      expect(find.text('✕ Your choice: sign 2.4'), findsOneWidget);
      expect(find.text('Correct answer:'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });
  });

  group('RoadSignsScreen Flow & Session Tests', () {
    testWidgets('Screen renders header, lives, time bar, prompt, and 4 cards', (tester) async {
      setupViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          RoadSignsScreen(
            initialDeck: [testQuestion1, testQuestion2],
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Header components
      expect(find.byType(GameLives), findsOneWidget);
      expect(find.byType(GameScoreLabel), findsOneWidget);
      expect(find.byType(GameTimeBar), findsOneWidget);

      // Prompt and grid
      expect(find.text(testQuestion1.prompt), findsOneWidget);
      expect(find.byType(RoadSignsGrid), findsOneWidget);
      expect(find.byType(InkWell), findsWidgets);
    });

    testWidgets('Correct answer blitz flow updates score and seamlessly advances after highlight', (tester) async {
      setupViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          RoadSignsScreen(
            initialDeck: [testQuestion1, testQuestion2],
            initialSeconds: 60,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Initial score is 0
      expect(find.text('0'), findsOneWidget);

      // Tap correct option (index 0 for testQuestion1)
      final gridCards = find.descendant(
        of: find.byType(RoadSignsGrid),
        matching: find.byType(InkWell),
      );
      expect(gridCards, findsNWidgets(4));

      await tester.tap(gridCards.at(0));
      await tester.pump();

      // No blocking modal during blitz
      expect(find.byType(RoadSignsModal), findsNothing);

      // Wait 450ms highlight delay
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump();

      // Seamlessly advanced to question 2
      expect(find.text(testQuestion2.prompt), findsOneWidget);

      // Score increased by GameEconomy.signs(1) = 12
      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('Incorrect answer blitz flow reduces lives, resets combo, and advances after highlight', (tester) async {
      setupViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          RoadSignsScreen(
            initialDeck: [testQuestion1, testQuestion2],
            initialLives: 5,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap wrong option (index 1 is 2.4, not 2.1)
      final gridCards = find.descendant(
        of: find.byType(RoadSignsGrid),
        matching: find.byType(InkWell),
      );
      await tester.tap(gridCards.at(1));
      await tester.pump();

      // No blocking modal during blitz
      expect(find.byType(RoadSignsModal), findsNothing);

      // Wait 800ms error highlight delay
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();

      // Combo is 0, score remains 0, advanced to question 2
      expect(find.text('0'), findsOneWidget);
      expect(find.text(testQuestion2.prompt), findsOneWidget);
    });

    testWidgets('Game ends when lives run out, showing GameResultOverlay with mistake review', (tester) async {
      setupViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          RoadSignsScreen(
            initialDeck: [testQuestion1, testQuestion2],
            initialLives: 1, // Only 1 life!
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap wrong option (index 1) to lose the only life
      final gridCards = find.descendant(
        of: find.byType(RoadSignsGrid),
        matching: find.byType(InkWell),
      );
      await tester.tap(gridCards.at(1));
      await tester.pump();

      // Error highlight 800ms finishes and triggers GameResultOverlay because lives == 0
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();

      expect(find.byType(GameResultOverlay), findsOneWidget);
      expect(find.byType(RoadSignsGrid), findsNothing);
    });

    testWidgets('Game ends when time runs out, showing GameResultOverlay with timeUp title', (tester) async {
      setupViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          RoadSignsScreen(
            initialDeck: [testQuestion1, testQuestion2],
            initialSeconds: 2,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Wait 3 seconds for timer to expire
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(GameResultOverlay), findsOneWidget);
    });

    testWidgets('Completing game updates roadSignsProgressProvider state and high score', (tester) async {
      setupViewport(tester);
      final progress = ProgressDataSource();
      await progress.init();
      final container = ProviderContainer(
        overrides: [
          progressDataSourceProvider.overrideWithValue(progress),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(roadSignsProgressProvider).bestScore, 0);
      expect(container.read(roadSignsProgressProvider).totalCorrect, 0);
      expect(container.read(roadSignsProgressProvider).totalAnswered, 0);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: RoadSignsScreen(
              initialDeck: [testQuestion1, testQuestion2],
              initialLives: 1,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap correct answer on question 1 (index 0)
      final gridCards = find.descendant(
        of: find.byType(RoadSignsGrid),
        matching: find.byType(InkWell),
      );
      await tester.tap(gridCards.at(0));
      await tester.pump();

      // Blitz delay advances to question 2
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump();

      // Question 2: tap wrong answer (index 0 is sign24, correct is index 1 sign31) -> loses last life
      final gridCardsQ2 = find.descendant(
        of: find.byType(RoadSignsGrid),
        matching: find.byType(InkWell),
      );
      await tester.tap(gridCardsQ2.at(0));
      await tester.pump();

      // Error blitz delay completes and ends the game because lives == 0
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();

      // Verify GameResultOverlay is shown
      expect(find.byType(GameResultOverlay), findsOneWidget);

      // Verify roadSignsProgressProvider updated
      final updatedState = container.read(roadSignsProgressProvider);
      expect(updatedState.bestScore, greaterThan(0));
      expect(updatedState.totalCorrect, 1);
      expect(updatedState.totalAnswered, 2);
    });
  });
}
