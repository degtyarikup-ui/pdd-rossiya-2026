import 'package:pdd_app/presentation/screens/games/widgets/mini_game_hud.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/config/game_economy.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/sources/sign_scenarios_library.dart';
import 'package:pdd_app/data/models/sign_swiper_model.dart';
import 'package:pdd_app/data/models/traffic_controller_progress.dart';
import 'package:pdd_app/data/models/crossroads_priority_progress.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/domain/services/sign_swiper_engine.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/games/games_hub_screen.dart';
import 'package:pdd_app/presentation/screens/games/sign_swiper/sign_swiper_screen.dart';
import 'package:pdd_app/presentation/screens/games/road_signs/road_signs_screen.dart';
import 'package:pdd_app/presentation/screens/games/sign_swiper/widgets/swipe_card_view.dart';
import 'package:pdd_app/presentation/screens/game/godot_game.dart';
import 'package:pdd_app/presentation/screens/games/widgets/game_ui.dart';
import 'package:pdd_app/presentation/screens/games/widgets/game_art.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProgressDataSource progress;
  late Map<String, dynamic> signs;
  late _TrafficWebPlatform web;
  WebViewPlatform? originalWebPlatform;

  setUpAll(() async {
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
    signs =
        jsonDecode(
              await rootBundle.loadString(
                'assets/countries/ru/questions/signs.json',
              ),
            )
            as Map<String, dynamic>;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    GodotGame.resetForTest();
    progress = ProgressDataSource();
    await progress.init();
    SoundEffectsService.instance.setEnabled(false);
    originalWebPlatform = WebViewPlatform.instance;
    web = _TrafficWebPlatform();
    WebViewPlatform.instance = web;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('pdd/godot_game'), (
          call,
        ) async {
          if (call.method == 'available') return false;
          return null;
        });
  });

  tearDown(() {
    SoundEffectsService.instance.setEnabled(true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('pdd/godot_game'), null);
    if (originalWebPlatform != null) {
      WebViewPlatform.instance = originalWebPlatform;
    }
  });

  Future<void> open(
    WidgetTester tester,
    Widget screen, {
    double textScale = 1,
    bool disableAnimations = false,
    Size size = const Size(390, 844),
    Map<String, dynamic>? signData,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isAuthenticatedProvider.overrideWithValue(true),
          progressDataSourceProvider.overrideWithValue(progress),
          signsProvider.overrideWith((ref) async => signData ?? signs),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: disableAnimations,
            ),
            child: child!,
          ),
          home: screen,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  void expectNoModeChoice() {
    expect(find.text('Обучение'), findsNothing);
    expect(find.text('Блиц'), findsNothing);
  }

  Future<void> answerSign(WidgetTester tester, {required bool correct}) async {
    final card = tester.widget<SwipeCardView>(find.byType(SwipeCardView)).card;
    final swipeRight = correct ? card.isCorrect : !card.isCorrect;
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is GameRoundButton &&
            widget.label ==
                (swipeRight ? card.rightActionLabel : card.leftActionLabel),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pump(Duration(milliseconds: correct ? 410 : 960));
    await tester.pump(const Duration(milliseconds: 330));
    await tester.pump();
  }

  testWidgets(
    'Godot regulator passes settings and saves every restarted round once',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      HapticFeedbackHelper.setEnabled(false);
      addTearDown(() => HapticFeedbackHelper.setEnabled(true));
      await progress.saveTrafficControllerProgress(
        const TrafficControllerProgress(bestScore: 72, totalSolved: 3),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('game_vehicle', 'sedan');
      await prefs.setString('game_vehicle_paint', 'red');
      List<String>? launch;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('pdd/godot_game'), (
            call,
          ) async {
            if (call.method != 'start') return true;
            launch = List<String>.from((call.arguments as Map)['args'] as List);
            return jsonEncode({
              'game': 'regulator',
              'runs': [
                {
                  'id': 'first',
                  'score': 100,
                  'solved': 4,
                  'wrong': 1,
                  'combo': 3,
                  'finished': true,
                },
                {
                  'id': 'first',
                  'score': 100,
                  'solved': 4,
                  'wrong': 1,
                  'combo': 3,
                  'finished': true,
                },
                {
                  'id': 'second',
                  'score': 24,
                  'solved': 1,
                  'wrong': 0,
                  'combo': 1,
                  'finished': false,
                },
                {
                  'id': 'empty',
                  'score': 0,
                  'solved': 0,
                  'wrong': 0,
                  'combo': 0,
                },
              ],
            });
          });
      await open(
        tester,
        Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => GodotGame.playRegulator(context, ref),
            child: const Text('Launch'),
          ),
        ),
      );
      await tester.tap(find.text('Launch'));
      await tester.pumpAndSettle();
      expect(
        launch,
        containsAll([
          '--regulator',
          '--best-score=72',
          '--mute',
          '--no-haptics',
          '--vehicle=sedan',
        ]),
      );
      final economy =
          jsonDecode(
                launch!
                    .singleWhere((s) => s.startsWith('--economy='))
                    .substring('--economy='.length),
              )
              as Map;
      expect(economy['base'], GameEconomy.regulator(1));
      expect(economy['maxScore'], GameEconomy.maxRunScore);
      expect(progress.getTrafficControllerProgress().bestScore, 100);
      expect(progress.getTrafficControllerProgress().maxCombo, 3);
      expect(progress.getTrafficControllerProgress().totalSolved, 8);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'Godot crossroads passes settings and saves every restarted round once',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      HapticFeedbackHelper.setEnabled(false);
      addTearDown(() => HapticFeedbackHelper.setEnabled(true));
      await progress.saveCrossroadsPriorityProgress(
        const CrossroadsPriorityProgress(bestScore: 80, totalSolved: 2),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('game_vehicle', 'suv');
      await prefs.setString('game_vehicle_paint', 'blue');
      List<String>? launch;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('pdd/godot_game'), (
            call,
          ) async {
            if (call.method != 'start') return true;
            launch = List<String>.from((call.arguments as Map)['args'] as List);
            return jsonEncode({
              'game': 'crossroads',
              'runs': [
                {
                  'id': 'first',
                  'score': 120,
                  'solved': 3,
                  'wrong': 1,
                  'combo': 2,
                  'finished': true,
                },
                {
                  'id': 'first',
                  'score': 120,
                  'solved': 3,
                  'wrong': 1,
                  'combo': 2,
                  'finished': true,
                },
                {
                  'id': 'second',
                  'score': 40,
                  'solved': 1,
                  'wrong': 0,
                  'combo': 1,
                  'finished': false,
                },
                {
                  'id': 'empty',
                  'score': 0,
                  'solved': 0,
                  'wrong': 0,
                  'combo': 0,
                },
              ],
            });
          });
      await open(
        tester,
        Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => GodotGame.playCrossroads(context, ref),
            child: const Text('Launch'),
          ),
        ),
      );
      await tester.tap(find.text('Launch'));
      await tester.pumpAndSettle();
      expect(
        launch,
        containsAll([
          '--crossroads',
          '--best-score=80',
          '--mute',
          '--no-haptics',
          '--vehicle=suv',
        ]),
      );
      final economy =
          jsonDecode(
                launch!
                    .singleWhere((s) => s.startsWith('--economy='))
                    .substring('--economy='.length),
              )
              as Map;
      expect(economy['base'], GameEconomy.crossroads(1));
      expect(economy['maxScore'], GameEconomy.maxRunScore);
      expect(progress.getCrossroadsPriorityProgress().bestScore, 120);
      expect(progress.getCrossroadsPriorityProgress().maxCombo, 2);
      expect(progress.getCrossroadsPriorityProgress().totalSolved, 6);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('Swiper starts immediately, expires once and restarts', (
    tester,
  ) async {
    await open(tester, const SignSwiperScreen());
    expectNoModeChoice();
    expect(find.byType(SwipeCardView), findsOneWidget);
    expect(
      tester.widget<GameTimeBar>(find.byType(GameTimeBar)).secondsLeft,
      60,
    );
    expect(tester.widget<GameLives>(find.byType(GameLives)).lives, 5);
    expect(tester.widget<GameScoreLabel>(find.byType(GameScoreLabel)).score, 0);

    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.widget<GameTimeBar>(find.byType(GameTimeBar)).secondsLeft,
      59,
    );
    await tester.pump(const Duration(seconds: 59));
    expect(find.text(appL10n.gameTimeUp), findsOneWidget);
    expect(find.byType(GameResultOverlay), findsOneWidget);
    expect(tester.widget<GameTimeBar>(find.byType(GameTimeBar)).secondsLeft, 0);

    await tester.tap(find.text(appL10n.gameRestart));
    await tester.pump();
    expect(find.byType(GameResultOverlay), findsNothing);
    expect(
      tester.widget<GameTimeBar>(find.byType(GameTimeBar)).secondsLeft,
      60,
    );
    expect(tester.widget<GameLives>(find.byType(GameLives)).lives, 5);
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.widget<GameTimeBar>(find.byType(GameTimeBar)).secondsLeft,
      59,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Swiper preserves earned points and ends after five mistakes', (
    tester,
  ) async {
    await open(tester, const SignSwiperScreen());
    await answerSign(tester, correct: true);
    expect(
      tester.widget<GameScoreLabel>(find.byType(GameScoreLabel)).score,
      12,
    );
    for (var mistakes = 1; mistakes <= 5; mistakes++) {
      await answerSign(tester, correct: false);
      expect(
        tester.widget<GameLives>(find.byType(GameLives)).lives,
        5 - mistakes,
      );
      expect(
        tester.widget<GameScoreLabel>(find.byType(GameScoreLabel)).score,
        12,
      );
    }
    expect(find.byType(GameResultOverlay), findsOneWidget);
    expect(progress.getSignSwiperProgress().bestScore, 12);
    expect(progress.getSignSwiperProgress().totalSwiped, 6);
    expect(progress.getSignSwiperProgress().trainingCount, 0);

    await tester.tap(find.text(appL10n.gameRunMistakesButton(5)));
    // The result rays turn endlessly: wait for the sheet, not for a settle.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Last lost life shows its answer before the results cover it', (
    tester,
  ) async {
    await open(tester, const SignSwiperScreen());
    for (var i = 0; i < 4; i++) {
      await answerSign(tester, correct: false);
    }
    final view = tester.widget<SwipeCardView>(find.byType(SwipeCardView));
    if (view.card.isCorrect) {
      view.controller!.swipeLeft();
    } else {
      view.controller!.swipeRight();
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(tester.widget<GameLives>(find.byType(GameLives)).lives, 0);
    expect(find.byType(GameLifeLossBadge), findsOneWidget);
    expect(find.byType(GameResultOverlay), findsNothing);
    await tester.pump(const Duration(milliseconds: 960));
    await tester.pump(const Duration(milliseconds: 330));
    expect(find.byType(GameResultOverlay), findsOneWidget);
    expect(progress.getSignSwiperProgress().totalSwiped, 5);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Clock reaching zero lets the accepted answer finish once', (
    tester,
  ) async {
    await open(tester, const SignSwiperScreen());
    await tester.pump(const Duration(seconds: 59));
    final view = tester.widget<SwipeCardView>(find.byType(SwipeCardView));
    if (view.card.isCorrect) {
      view.controller!.swipeLeft();
    } else {
      view.controller!.swipeRight();
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pump(const Duration(milliseconds: 850));
    expect(tester.widget<GameTimeBar>(find.byType(GameTimeBar)).secondsLeft, 0);
    expect(find.byType(GameResultOverlay), findsNothing);
    expect(find.byType(GameLifeLossBadge), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 330));
    expect(find.byType(GameResultOverlay), findsOneWidget);
    expect(progress.getSignSwiperProgress().totalSwiped, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Empty signs show a retry state without starting a round', (
    tester,
  ) async {
    await open(tester, const SignSwiperScreen(), signData: {});
    expect(find.text(appL10n.gameSignsLoadError), findsOneWidget);
    expect(find.text(appL10n.gameRetry), findsOneWidget);
    expect(find.byType(SwipeCardView), findsNothing);
    expect(find.byType(GameTimeBar), findsNothing);
    await tester.pump(const Duration(seconds: 65));
    expect(find.byType(GameResultOverlay), findsNothing);
    expect(progress.getSignSwiperProgress().totalSwiped, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Swiper timer is fixed while correct and wrong answers preserve progress',
    (tester) async {
      await open(tester, const SignSwiperScreen());
      final startedAt = tester.binding.clock.now();
      var previousScore = 0;
      for (final correct in [true, true, false, true, false, true, false]) {
        await answerSign(tester, correct: correct);
        final score = tester
            .widget<GameScoreLabel>(find.byType(GameScoreLabel))
            .score;
        expect(score, correct ? greaterThan(previousScore) : previousScore);
        previousScore = score;
        final elapsed = tester.binding.clock.now().difference(startedAt);
        expect(
          tester.widget<GameTimeBar>(find.byType(GameTimeBar)).secondsLeft,
          60 - elapsed.inSeconds,
        );
      }
      expect(tester.widget<GameLives>(find.byType(GameLives)).lives, 2);
      expect(find.byType(GameResultOverlay), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Swiper perfect play has bounded rewards and ends at sixty seconds',
    (tester) async {
      await open(tester, const SignSwiperScreen());
      final startedAt = tester.binding.clock.now();
      for (var i = 0; i < 50; i++) {
        await answerSign(tester, correct: true);
      }
      expect(
        tester.widget<GameScoreLabel>(find.byType(GameScoreLabel)).score,
        List.generate(
          50,
          (i) => GameEconomy.signs(i + 1),
        ).reduce((a, b) => a + b),
      );
      expect(tester.widget<GameLives>(find.byType(GameLives)).lives, 5);
      final elapsed = tester.binding.clock.now().difference(startedAt);
      await tester.pump(const Duration(seconds: 60) - elapsed);
      expect(find.byType(GameResultOverlay), findsOneWidget);
      expect(find.text(appL10n.gameTimeUp), findsOneWidget);
      expect(
        progress.getSignSwiperProgress().bestScore,
        lessThanOrEqualTo(GameEconomy.maxRunScore),
      );
      expect(progress.getSignSwiperProgress().totalSwiped, 50);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Swipe commits once, cancels safely and honors reduced motion', (
    tester,
  ) async {
    final card = SignSwiperEngine(
      allSigns: SignSwiperEngine.parseSignsJson(signs),
    ).generateDeck(count: 1).single;
    final controller = SwipeCardController();
    final swipes = <bool>[];
    Widget view() => Scaffold(
      body: Center(
        child: SizedBox(
          width: 300,
          height: 500,
          child: SwipeCardView(
            card: card,
            controller: controller,
            onSwiped: swipes.add,
          ),
        ),
      ),
    );
    await open(tester, view());
    await tester.pump(const Duration(milliseconds: 300));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SwipeCardView)),
    );
    await gesture.moveBy(const Offset(50, 0));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(swipes, isEmpty);
    controller.swipeRight();
    controller.swipeLeft();
    await tester.pumpAndSettle();
    expect(swipes, [true]);
    controller.swipeLeft();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
    controller.swipeRight();
    expect(swipes, [true]);

    await open(tester, view(), disableAnimations: true);
    controller.swipeLeft();
    await tester.pumpAndSettle();
    expect(swipes, [true, false]);
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Swiper result uses the shared full-screen format', (
    tester,
  ) async {
    var restarts = 0, exits = 0, mistakes = 0;
    await open(
      tester,
      Scaffold(
        body: GameResultOverlay(
          emblem: const SignSwiperEmblem(),
          title: appL10n.gameOverTitle,
          score: 3900,
          bestScore: 1500,
          isNewRecord: false,
          stats: [
            GameResultStat(appL10n.gameCorrectAnswers, '10/13'),
            GameResultStat(appL10n.gameComboLabel, 'x8'),
          ],
          mistakesCount: 3,
          onMistakes: () => mistakes++,
          onRestart: () => restarts++,
          onExit: () => exits++,
        ),
      ),
      size: const Size(320, 568),
      textScale: 1.6,
    );
    // The rays keep turning: settle the counters, not the endless rotation.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('3900'), findsOneWidget);
    expect(find.text('10/13'), findsOneWidget);
    expect(find.text(appL10n.gameBestScore(1500)), findsOneWidget);
    await tester.tap(find.text(appL10n.gameRestart));
    await tester.tap(find.text(appL10n.gameRunMistakesButton(3)));
    await tester.tap(find.byTooltip(appL10n.gameExit));
    expect((restarts, mistakes, exits), (1, 1, 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Hub cover cards remain readable at 320px and large text', (
    tester,
  ) async {
    await progress.saveTrafficControllerProgress(
      const TrafficControllerProgress(bestScore: 123456789),
    );
    await progress.saveSignSwiperProgress(
      const SignSwiperProgress(bestScore: 987654321),
    );
    await open(
      tester,
      const GamesHubScreen(),
      size: const Size(320, 740),
      textScale: 1.6,
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Жесты регулировщика глазами водителя: разберитесь в обучении и проверьте себя в блице.',
      ),
      findsNothing,
    );
    expect(
      find.text(
        'Ситуации со знаками: свайп вправо — «да», влево — «нет». Разбор каждой ошибки.',
      ),
      findsNothing,
    );
    for (final titleAndRecord in [
      (
        appL10n.gameTrafficControllerTitle,
        appL10n.gamesRecordScore(
          NumberFormat.decimalPattern('ru').format(123456789),
        ),
      ),
      (
        appL10n.gamesSignsTitle,
        appL10n.gamesRecordScore(
          NumberFormat.decimalPattern('ru').format(987654321),
        ),
      ),
    ]) {
      await tester.scrollUntilVisible(find.text(titleAndRecord.$1), 200);
      await tester.pumpAndSettle();
      expect(find.text(titleAndRecord.$2), findsOneWidget);
      final cardStack = find
          .ancestor(
            of: find.text(titleAndRecord.$1),
            matching: find.byType(Stack),
          )
          .first;
      final photo = find.descendant(
        of: cardStack,
        matching: find.byType(Image),
      );
      expect(photo, findsOneWidget);
      final photoRect = tester.getRect(photo.first);
      expect(photoRect.height, greaterThanOrEqualTo(190));
      for (final label in [titleAndRecord.$1, titleAndRecord.$2]) {
        final labelRect = tester.getRect(find.text(label));
        expect(labelRect.left, greaterThanOrEqualTo(photoRect.left));
        expect(labelRect.right, lessThanOrEqualTo(photoRect.right));
        expect(labelRect.top, greaterThanOrEqualTo(photoRect.top));
        expect(labelRect.bottom, lessThanOrEqualTo(photoRect.bottom));
      }
    }
    await tester.scrollUntilVisible(
      find.text(appL10n.gamesCrossroadsTitle),
      200,
    );
    await tester.tapAt(
      tester.getCenter(find.text(appL10n.gamesCrossroadsTitle)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(appL10n.gameUnavailable), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(GamesHubScreen), findsOneWidget);
    await tester.scrollUntilVisible(find.text(appL10n.gamesParkingTitle), 200);
    await tester.pumpAndSettle();
    expect(find.text(appL10n.gameSoonBadge), findsNothing);
    await tester.tapAt(tester.getCenter(find.text(appL10n.gamesParkingTitle)));
    await tester.pumpAndSettle();
    expect(find.byType(GamesHubScreen), findsOneWidget);
    expect(find.byType(SignSwiperScreen), findsNothing);
    expect(tester.takeException(), isNull);
    // Violator game checks Godot availability
    await tester.scrollUntilVisible(find.text(appL10n.gamesViolatorTitle), 200);
    await tester.tapAt(tester.getCenter(find.text(appL10n.gamesViolatorTitle)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(appL10n.gameUnavailable), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(GamesHubScreen), findsOneWidget);
    // Road signs game opens RoadSignsScreen
    await tester.scrollUntilVisible(
      find.text(appL10n.gamesRoadSignsTitle),
      -200,
    );
    await tester.tapAt(
      tester.getCenter(find.text(appL10n.gamesRoadSignsTitle)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RoadSignsScreen), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(GamesHubScreen), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text(appL10n.gameTrafficControllerTitle),
      -200,
    );
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getCenter(find.text(appL10n.gameTrafficControllerTitle)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(appL10n.gameUnavailable), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Swiper game fits at 320px with accessible text', (tester) async {
    await open(
      tester,
      const SignSwiperScreen(),
      size: const Size(320, 740),
      textScale: 1.6,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SwipeCardView), findsOneWidget);
    final cardSize = tester.getSize(find.byType(SwipeCardView));
    final realCards = [
      for (final sign in SignSwiperEngine.parseSignsJson(signs))
        for (final scenario
            in SignScenariosLibrary.getScenariosForSign(sign.number) ??
                <SignScenario>[])
          SignCardQuestion(
            id: '${sign.number}_${scenario.prompt}',
            sign: sign,
            prompt: scenario.prompt,
            isCorrect: scenario.isCorrect,
            explanation: scenario.explanation,
            type: scenario.type,
          ),
    ]..sort((a, b) => b.prompt.length.compareTo(a.prompt.length));
    final swipes = <bool>[];
    final cardController = SwipeCardController();
    // Exercise the longest real question at the space the game actually gives
    // its card. The generated first card must not make layout QA random.
    await open(
      tester,
      Scaffold(
        body: Center(
          child: SizedBox.fromSize(
            size: cardSize,
            child: SwipeCardView(
              card: realCards.first,
              controller: cardController,
              onSwiped: swipes.add,
            ),
          ),
        ),
      ),
      size: const Size(320, 740),
      textScale: 1.6,
    );
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(SwipeCardView), const Offset(0, -160));
    await tester.pumpAndSettle();
    expect(swipes, isEmpty);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.pixels, greaterThan(0));
    await tester.drag(find.byType(SwipeCardView), const Offset(160, 0));
    await tester.pumpAndSettle();
    expect(swipes, [true]);
    cardController.swipeLeft();
    await tester.pumpAndSettle();
    expect(swipes, [true, false]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('A first time player opens a running swiper from its cover', (
    tester,
  ) async {
    await open(tester, const GamesHubScreen());
    await tester.scrollUntilVisible(find.text(appL10n.gamesSignsTitle), 200);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.text(appL10n.gamesSignsTitle)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.byType(SignSwiperScreen), findsOneWidget);
    expect(find.byType(SwipeCardView), findsOneWidget);
    expectNoModeChoice();
    expect(
      tester.widget<GameTimeBar>(find.byType(GameTimeBar)).secondsLeft,
      60,
    );
    await tester.pumpWidget(const SizedBox());
  });
}

/// Executes the actual screen bridge without requiring an iOS/Android view.
class _TrafficWebPlatform extends WebViewPlatform {
  final controllers = <_TrafficWebController>[];

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = _TrafficWebController(params);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _TrafficNavigation(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _TrafficWebWidget(params);
}

class _TrafficNavigation extends PlatformNavigationDelegate {
  _TrafficNavigation(super.params) : super.implementation();

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {}
}

class _TrafficWebController extends PlatformWebViewController {
  _TrafficWebController(super.params) : super.implementation();
  final scripts = <String>[];
  late JavaScriptChannelParams channel;

  void emitReady() => channel.onMessageReceived(
    const JavaScriptMessage(message: '{"type":"ready"}'),
  );

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    channel = params;
  }

  @override
  Future<void> loadFlutterAsset(String key) async {}

  @override
  Future<void> runJavaScript(String script) async {
    scripts.add(script);
  }
}

class _TrafficWebWidget extends PlatformWebViewWidget {
  _TrafficWebWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
