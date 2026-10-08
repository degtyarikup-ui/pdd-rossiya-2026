import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/datasources/sign_scenarios_library.dart';
import 'package:pdd_app/data/models/sign_swiper_model.dart';
import 'package:pdd_app/data/models/traffic_controller_progress.dart';
import 'package:pdd_app/data/models/traffic_controller_rules.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/domain/services/sign_swiper_engine.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/games/games_hub_screen.dart';
import 'package:pdd_app/presentation/screens/games/sign_swiper/sign_swiper_screen.dart';
import 'package:pdd_app/presentation/screens/games/sign_swiper/widgets/swipe_card_view.dart';
import 'package:pdd_app/presentation/screens/games/traffic_controller/traffic_controller_screen.dart';
import 'package:pdd_app/presentation/screens/games/widgets/game_ui.dart';
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
    progress = ProgressDataSource();
    await progress.init();
    SoundEffectsService.instance.setEnabled(false);
    originalWebPlatform = WebViewPlatform.instance;
    web = _TrafficWebPlatform();
    WebViewPlatform.instance = web;
  });

  tearDown(() {
    SoundEffectsService.instance.setEnabled(true);
    if (originalWebPlatform != null) {
      WebViewPlatform.instance = originalWebPlatform;
    }
  });

  Future<void> open(
    WidgetTester tester,
    Widget screen, {
    double textScale = 1,
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
          progressDataSourceProvider.overrideWithValue(progress),
          signsProvider.overrideWith((ref) async => signData ?? signs),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
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
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump();
  }

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
    expect(tester.widget<GameLives>(find.byType(GameLives)).lives, 3);
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
    expect(tester.widget<GameLives>(find.byType(GameLives)).lives, 3);
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.widget<GameTimeBar>(find.byType(GameTimeBar)).secondsLeft,
      59,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Swiper scores correct answers and ends after three mistakes', (
    tester,
  ) async {
    await open(tester, const SignSwiperScreen());
    await answerSign(tester, correct: true);
    expect(
      tester.widget<GameScoreLabel>(find.byType(GameScoreLabel)).score,
      100,
    );
    for (var mistakes = 1; mistakes <= 3; mistakes++) {
      await answerSign(tester, correct: false);
      expect(
        tester.widget<GameLives>(find.byType(GameLives)).lives,
        3 - mistakes,
      );
    }
    expect(find.byType(GameResultOverlay), findsOneWidget);
    expect(progress.getSignSwiperProgress().bestScore, 100);
    expect(progress.getSignSwiperProgress().totalSwiped, 4);
    expect(progress.getSignSwiperProgress().trainingCount, 0);

    await tester.tap(find.text(appL10n.gameRunMistakesButton(3)));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
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

  testWidgets('Traffic round begins when the scene is ready and counts down', (
    tester,
  ) async {
    await open(tester, const TrafficControllerScreen());
    expectNoModeChoice();
    // Loading the 3D scene does not consume the answer time.
    await tester.pump(const Duration(seconds: 10));
    expect(find.text(appL10n.gameSecondsLeft(25)), findsNothing);
    web.controllers.single.emitReady();
    await tester.pump();
    expect(find.text(appL10n.gameSecondsLeft(35)), findsOneWidget);
    expect(tester.widget<GameLives>(find.byType(GameLives)).lives, 3);
    expect(
      web.controllers.single.scripts,
      contains(contains('setMode("arcade")')),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(appL10n.gameSecondsLeft(34)), findsOneWidget);
    web.controllers.single.emitReady();
    await tester.pump();
    expect(find.text(appL10n.gameSecondsLeft(34)), findsOneWidget);
    await tester.pump(const Duration(seconds: 34));
    expect(find.byType(GameResultOverlay), findsOneWidget);
    expect(find.text(appL10n.gameTimeUp), findsOneWidget);
    await tester.tap(find.text(appL10n.gameRestart));
    await tester.pump();
    expect(find.byType(GameResultOverlay), findsNothing);
    expect(find.text(appL10n.gameSecondsLeft(35)), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Traffic actions follow driving directions and fit large text', (
    tester,
  ) async {
    await open(
      tester,
      const TrafficControllerScreen(),
      size: const Size(320, 568),
      textScale: 2,
    );
    for (final move in TrafficMove.values) {
      final button = find.ancestor(
        of: find.text(_moveLabel(move)),
        matching: find.byType(InkWell),
      );
      expect(tester.widget<InkWell>(button).onTap, isNull);
    }
    web.controllers.single.emitReady();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expectNoModeChoice();
    final left = tester.getCenter(find.text(appL10n.gameActionLeft));
    final straight = tester.getCenter(find.text(appL10n.gameActionStraight));
    final right = tester.getCenter(find.text(appL10n.gameActionRight));
    final turn = tester.getCenter(find.text(appL10n.gameActionUTurn));
    final stop = tester.getCenter(find.text(appL10n.gameActionStand));
    expect(left.dx, lessThan(straight.dx));
    expect(straight.dx, lessThan(right.dx));
    expect(left.dy, closeTo(straight.dy, 1));
    expect(right.dy, closeTo(straight.dy, 1));
    expect(turn.dy, greaterThan(straight.dy));
    expect(turn.dy, closeTo(stop.dy, 1));
    expect(turn.dx, lessThan(stop.dx));
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(find.byIcon(Icons.remove_rounded), findsNothing);
    for (final move in TrafficMove.values) {
      final button = find.ancestor(
        of: find.text(_moveLabel(move)),
        matching: find.byType(InkWell),
      );
      final bounds = tester.getRect(button);
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(320));
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.bottom, lessThanOrEqualTo(568));
      expect(tester.widget<InkWell>(button).onTap, isNotNull);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Traffic scores a move once and ends after three mistakes', (
    tester,
  ) async {
    await open(tester, const TrafficControllerScreen());
    final controller = web.controllers.single..emitReady();
    await tester.pump();
    final correct = controller.allowedMoves.first;
    await tester.tap(find.text(_moveLabel(correct)));
    await tester.pump();
    await tester.tap(find.text(_moveLabel(correct)));
    await tester.pump();
    expect(
      tester.widget<GameScoreLabel>(find.byType(GameScoreLabel)).score,
      100,
    );
    await tester.pump(const Duration(milliseconds: 1300));

    for (var mistakes = 1; mistakes <= 3; mistakes++) {
      final allowed = controller.allowedMoves;
      final wrong = TrafficMove.values.firstWhere(
        (move) => !allowed.contains(move),
      );
      await tester.tap(find.text(_moveLabel(wrong)));
      await tester.pump();
      expect(
        tester.widget<GameLives>(find.byType(GameLives)).lives,
        3 - mistakes,
      );
      if (mistakes < 3) {
        await tester.pump(const Duration(milliseconds: 1200));
      }
    }
    expect(find.byType(GameResultOverlay), findsOneWidget);
    expect(progress.getTrafficControllerProgress().bestScore, 100);
    expect(progress.getTrafficControllerProgress().totalSolved, 1);
    expect(progress.getTrafficControllerProgress().trainingCount, 0);
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
    expect(find.text(appL10n.gameBestScore(123456789)), findsOneWidget);
    expect(find.text(appL10n.gameBestScore(987654321)), findsOneWidget);
    expect(find.byType(ImageFiltered), findsNWidgets(2));
    for (final titleAndRecord in [
      (appL10n.gameTrafficControllerTitle, appL10n.gameBestScore(123456789)),
      (appL10n.gameSignSwiperTitle, appL10n.gameBestScore(987654321)),
    ]) {
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
      expect(photo, findsNWidgets(2));
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
    expect(tester.takeException(), isNull);
    await tester.tapAt(
      tester.getCenter(find.text(appL10n.gameTrafficControllerTitle)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(TrafficControllerScreen), findsOneWidget);
    expectNoModeChoice();
    web.controllers.single.emitReady();
    await tester.pump();
    expect(find.text(appL10n.gameSecondsLeft(35)), findsOneWidget);
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
    await tester.tapAt(
      tester.getCenter(find.text(appL10n.gameSignSwiperTitle)),
    );
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

String _moveLabel(TrafficMove move) => switch (move) {
  TrafficMove.straight => appL10n.gameActionStraight,
  TrafficMove.left => appL10n.gameActionLeft,
  TrafficMove.right => appL10n.gameActionRight,
  TrafficMove.uTurn => appL10n.gameActionUTurn,
  TrafficMove.none => appL10n.gameActionStand,
};

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

  Set<TrafficMove> get allowedMoves {
    final scenario = scripts.lastWhere(
      (script) => script.contains('setScenario('),
    );
    final args = RegExp(
      r'setScenario\("([^"]+)", "([^"]+)", "([^"]+)"\)',
    ).firstMatch(scenario)!;
    return TrafficControllerRules.allowedMoves(
      gesture: ControllerGesture.values.byName(args.group(1)!),
      approach: ApproachDirection.values.byName(args.group(2)!),
      vehicle: VehicleKind.values.byName(args.group(3)!),
    );
  }

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
