import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/services/game_garage_service.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_garage.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/presentation/screens/game/game_screen.dart';
// Native WebView seam: exercise the screen without a device platform view.
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_controls_overlay.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_debug_sheet.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_hud.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_question_card.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_over_dialog.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_explanation_sheet.dart';
import 'package:pdd_app/data/models/game_situation.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/presentation/screens/game/controllers/game_controller.dart';

/// The game screen is for signed-in players: tests override the auth flag.
final signedIn = [isAuthenticatedProvider.overrideWithValue(true)];

void main() {
  test('Garage unlocks cars after 5, 15, 35, 55 correct answers', () async {
    final garage = GameGarageService.instance..resetForTest();
    final unlockedAt = <int>[];
    for (var i = 1; i <= 80; i++) {
      final car = await garage.recordCorrect();
      if (car != null) unlockedAt.add(i);
    }
    expect(unlockedAt, [5, 15, 35, 55, 75]);
    expect(garage.cars.length, 6);
    // Every model is different until all six are owned.
    expect(garage.cars.map((c) => c.id).toSet().length, 6);
    expect(garage.cars.first, GameGarageService.starter);
    garage.resetForTest();
  });

  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SoundEffectsService.instance.setEnabled(false);
  });
  tearDown(() => SoundEffectsService.instance.setEnabled(true));

  testWidgets('Debug menu toggles unlimited fuel', (tester) async {
    bool? unlimited;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameDebugSheet(
            weatherOverride: null,
            seasonOverride: null,
            unlimitedFuel: false,
            onWeatherChanged: (_) {},
            onSeasonChanged: (_) {},
            onUnlimitedFuelChanged: (value) => unlimited = value,
          ),
        ),
      ),
    );

    expect(find.text(appL10n.gameDebugUnlimitedFuel), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(unlimited, isTrue);
  });

  testWidgets(
    'Question, explanation and results fit 320px at double text scale',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const situation = GameSituation(
        id: 'layout',
        ticket: 'Билет 40 · Вопрос 15',
        title: 'Кому Вы обязаны уступить дорогу?',
        explanation: 'Необходимо уступить дорогу обоим транспортным средствам.',
        pddRule: 'п. 13.9, 13.11',
        options: ['Первому', 'Второму', 'Обоим'],
        correctAnswerIndex: 2,
        legend: [],
        type: 'crossroad',
      );
      for (final child in [
        GameQuestionCard(
          state: const GameState(
            phase: GamePhase.situation,
            currentSituation: situation,
          ),
          onSelectAnswer: (_) {},
        ),
        GameExplanationSheet(situation: situation, onContinue: () {}),
        GameOverDialog(
          state: const GameState(phase: GamePhase.gameOver, score: 1234567),
          onRestart: () {},
          onExit: () {},
        ),
        GameOverDialog(
          state: const GameState(
            phase: GamePhase.gameOver,
            score: 1234567,
            fuel: 0,
            distanceM: 12345,
            violationCount: 12,
          ),
          fuelRefillAt: DateTime.now().add(const Duration(minutes: 30)),
          bestScore: 7654321,
          onLeaderboard: () {},
          onBuyPremium: () {},
          onRestart: () {},
        ),
        const GameGarage(
          selected: GameGarageService.starter,
          cars: [GameGarageService.starter, GameCar('coupe', 'teal')],
          premium: true,
          correctUntilNext: 5,
        ),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 740),
                textScaler: TextScaler.linear(2),
              ),
              child: Scaffold(body: Center(child: child)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '${child.runtimeType}');
      }
    },
  );

  testWidgets(
    'All controls fit narrow phones and remain usable at large text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final width in [320.0, 360.0, 390.0]) {
        tester.view.physicalSize = Size(width, 740);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 740),
                textScaler: const TextScaler.linear(2),
              ),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: GameControlsOverlay(
                    state: const GameState(phase: GamePhase.driving),
                    onGasChanged: (_) {},
                    onSwitchLane: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: 'width $width');
        for (final control in [
          find.byIcon(Icons.arrow_back_rounded),
          find.byIcon(Icons.arrow_forward_rounded),
          find.byKey(const ValueKey('game-gas')),
        ]) {
          final center = tester.getCenter(control);
          expect(center.dx, inInclusiveRange(20, width - 20));
        }
        final brake = tester.getRect(find.byKey(const ValueKey('game-brake')));
        final gas = tester.getRect(find.byKey(const ValueKey('game-gas')));
        expect(brake.center.dx, gas.center.dx);
        expect(brake.bottom + 10, gas.top);
      }
    },
  );

  testWidgets('Brake holds, cancels and releases when controls disable', (
    tester,
  ) async {
    final brake = <bool>[];
    Future<void> show(GameState state) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameControlsOverlay(
            state: state,
            onGasChanged: (_) {},
            onSwitchLane: (_) {},
            onBrake: brake.add,
          ),
        ),
      ),
    );
    await show(const GameState(phase: GamePhase.driving));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('game-brake'))),
    );
    expect(brake, [true]);
    await gesture.cancel();
    expect(brake, [true, false]);
    final held = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('game-brake'))),
    );
    await show(const GameState(phase: GamePhase.driving, recovering: true));
    expect(brake, [true, false, true, false]);
    await held.up();
    expect(brake.length, 4);
  });

  testWidgets('Driving controls vibrate once on press and never on release', (
    tester,
  ) async {
    final haptics = <Object?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameControlsOverlay(
            state: const GameState(phase: GamePhase.driving),
            onGasChanged: (_) {},
            onSwitchLane: (_) {},
            onSteering: (_) {},
            onBrake: (_) {},
          ),
        ),
      ),
    );

    final steering = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.arrow_back_rounded)),
    );
    await steering.moveBy(const Offset(5, 0));
    await steering.up();
    final gas = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('game-gas'))),
      pointer: 2,
    );
    await gas.up();
    final brake = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('game-brake'))),
      pointer: 3,
    );
    await brake.up();
    await tester.pump();

    expect(haptics, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.lightImpact',
    ]);
  });

  testWidgets(
    'Releasing either steering finger preserves the other held direction',
    (tester) async {
      final steering = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameControlsOverlay(
              state: const GameState(phase: GamePhase.driving),
              onGasChanged: (_) {},
              onSwitchLane: (_) {},
              onSteering: steering.add,
            ),
          ),
        ),
      );
      final left = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.arrow_back_rounded)),
        pointer: 1,
      );
      final right = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.arrow_forward_rounded)),
        pointer: 2,
      );
      expect(steering.last, -1);
      await left.up();
      expect(steering.last, -1);
      await right.up();
      expect(steering.last, 0);
      final left2 = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.arrow_back_rounded)),
        pointer: 3,
      );
      final right2 = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.arrow_forward_rounded)),
        pointer: 4,
      );
      await right2.up();
      expect(steering.last, 1);
      await left2.up();
      expect(steering.last, 0);
    },
  );

  testWidgets('Game tab opens on the garage start screen', (tester) async {
    final platform = _GameWebPlatform();
    WebViewPlatform.instance = platform;
    await tester.pumpWidget(
      ProviderScope(
        overrides: signedIn,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();
    final engine = platform.controllers.single;
    engine.emit('{"event":"ready"}');
    await tester.pump();
    // The garage: the engine is asked for it, the run waits, no controls.
    expect(engine.scripts.any((s) => s.contains('showLobby')), true);
    expect(find.text(appL10n.gameLobbyStart), findsOneWidget);
    expect(find.byType(GameControlsOverlay), findsNothing);
    await tester.tap(find.text(appL10n.gameLobbyStart));
    await tester.pump();
    expect(engine.scripts.any((s) => s.contains('hideLobby')), true);
    expect(find.byType(GameControlsOverlay), findsOneWidget);
    expect(find.text(appL10n.gameLobbyStart), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Impact releases native pedals until engine recovery completes', (
    tester,
  ) async {
    final platform = _GameWebPlatform();
    WebViewPlatform.instance = platform;
    await tester.pumpWidget(
      ProviderScope(
        overrides: signedIn,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();
    final engine = platform.controllers.single;
    engine.emit('{"event":"ready"}');
    await tester.pump();
    await _startDrive(tester);
    final gas = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('game-gas'))),
    );
    await tester.pump();
    engine.emit('{"event":"maneuver_reset"}');
    await tester.pump();
    var controls = tester.widget<GameControlsOverlay>(
      find.byType(GameControlsOverlay),
    );
    expect(controls.state.controlsEnabled, false);
    await gas.up();
    engine.emit('{"event":"maneuver_ready"}');
    await tester.pump();
    controls = tester.widget<GameControlsOverlay>(
      find.byType(GameControlsOverlay),
    );
    expect(controls.state.controlsEnabled, true);
    engine.scripts.clear();
    final retry = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('game-gas'))),
    );
    expect(engine.scripts.any((s) => s.contains('setGas(true)')), true);
    await retry.up();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Violation notice expires without resetting its counter', (
    tester,
  ) async {
    final controller = GameController();
    controller.onEngineReady();
    controller.recordViolation('collision', 1);
    await tester.pump(const Duration(seconds: 3));
    expect(controller.state.lastViolation, 'collision');
    controller.recordViolation('offroad', 2);
    await tester.pump(const Duration(seconds: 2));
    expect(controller.state.lastViolation, 'offroad');
    await tester.pump(const Duration(seconds: 2));
    expect(controller.state.lastViolation, isNull);
    expect(controller.state.violationCount, 2);
    controller.dispose();
  });

  testWidgets('Garage pauses driving, changes model and remembers choice', (
    tester,
  ) async {
    // A garage with the starter hatch and one earned car.
    SharedPreferences.setMockInitialValues({
      'game_garage_cars':
          '[{"id":"hatch","paint":"red"},{"id":"pickup","paint":"teal"}]',
    });
    GameGarageService.instance.resetForTest();
    final platform = _GameWebPlatform();
    WebViewPlatform.instance = platform;
    await tester.pumpWidget(
      ProviderScope(
        overrides: signedIn,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();
    final engine = platform.controllers.single;
    engine.emit('{"event":"ready"}');
    await tester.pump();
    await _startDrive(tester);
    // The car button in the HUD opens the garage over the paused run.
    engine.scripts.clear();
    await tester.tap(find.bySemanticsLabel(appL10n.gameGarage));
    await tester.pump();
    expect(engine.scripts.any((s) => s.contains('setPaused(true)')), true);
    expect(engine.scripts.any((s) => s.contains('showLobby')), true);
    expect(find.text(appL10n.gameLobbyContinue), findsOneWidget);
    // Arrows browse the earned cars only (hatch -> pickup), in their paint.
    await tester.tap(
      find.bySemanticsLabel(
        MaterialLocalizations.of(
          tester.element(find.byType(GameScreen)),
        ).nextPageTooltip,
      ),
      warnIfMissed: false,
    );
    await tester.pump();
    engine.emit('{"event":"vehicle_selected","vehicleId":"pickup"}');
    await tester.pump();
    expect(
      engine.scripts.any((s) => s.contains('selectVehicle("pickup","teal")')),
      true,
    );
    expect(
      engine.scripts.any((s) => s.contains('lobbySwap("pickup","teal",1)')),
      true,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('game_vehicle'), 'pickup');
    expect(prefs.getString('game_vehicle_paint'), 'teal');
    // «Continue the drive» returns to the same run.
    await tester.tap(find.text(appL10n.gameLobbyContinue));
    await tester.pump();
    expect(engine.scripts.any((s) => s.contains('hideLobby')), true);
    expect(find.byType(GameControlsOverlay), findsOneWidget);
    GameGarageService.instance.resetForTest();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Four short tram answers fit 402x874 without scrolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await (FontLoader(
      'Onest',
    )..addFont(rootBundle.load('assets/fonts/Onest-Regular.ttf'))).load();
    final situation = GameSituation.fromJson({
      'id': 'trams',
      'ticket': 'Билет 1 · Вопрос 14',
      'title':
          'Вы намерены проехать перекресток в прямом направлении. Кому Вы должны уступить дорогу?',
      'options': [
        'Обоим трамваям',
        'Только трамваю А',
        'Только трамваю Б',
        'Никому',
      ],
      'correctAnswerIndex': 0,
      'legend': [
        {'label': 'Вы прямо', 'color': '#ED4621'},
        {'label': 'Трамвай Б', 'color': '#FFA500'},
        {'label': 'Трамвай А', 'color': '#0574F8'},
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Onest'),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(402, 874),
              padding: EdgeInsets.only(bottom: 34),
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: GameQuestionCard(
                state: GameState(
                  phase: GamePhase.situation,
                  currentSituation: situation,
                ),
                onSelectAnswer: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.maxScrollExtent, 0);
    for (final option in situation.options) {
      final button = find.ancestor(
        of: find.text(option),
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    }
    for (final legend in situation.legend) {
      expect(find.text(legend.label), findsNothing);
    }
    expect(find.text('Никому').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Restart waits for native channel detachment; dispose detaches too',
    (tester) async {
      final platform = _GameWebPlatform();
      WebViewPlatform.instance = platform;
      await tester.pumpWidget(
        ProviderScope(
          overrides: signedIn,
          child: const MaterialApp(home: GameScreen()),
        ),
      );
      await tester.pump();
      final old = platform.controllers.single;
      old.emit('{"event":"ready"}');
      old.emit('{"event":"engine_error"}');
      await tester.pump();
      old.detachGate = Completer<void>();
      await tester.tap(find.text(appL10n.gameRestart));
      await tester.pump();
      expect(platform.controllers.length, 1);
      expect(old.channelRemoved, false);
      old.detachGate!.complete();
      await tester.pump();
      expect(old.channelRemoved, true);
      expect(platform.controllers.length, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(platform.controllers.last.channelRemoved, true);
    },
  );

  testWidgets(
    'HUD shows violations as an icon and number beside other metrics',
    (tester) async {
      Widget hud(int count) => MaterialApp(
        home: Scaffold(
          body: GameHud(
            state: GameState(phase: GamePhase.driving, violationCount: count),
          ),
        ),
      );
      await tester.pumpWidget(hud(0));
      expect(find.text('${appL10n.gameViolations}: 0'), findsNothing);
      expect(find.byKey(const ValueKey('hud-hud_warning')), findsOneWidget);
      // The fuel gauge replaced the hearts: a canister with five pips.
      expect(find.byKey(const ValueKey('hud-fuel')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('5 / 5')), findsOneWidget);
      await tester.pumpWidget(hud(2));
      final label = find.text('2');
      expect(label, findsOneWidget);
      final surface = tester.widget<Container>(
        find.ancestor(of: label, matching: find.byType(Container)).first,
      );
      expect((surface.decoration! as BoxDecoration).color, isNotNull);
    },
  );

  testWidgets(
    'Steering icons are available on both sides without visible labels',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameControlsOverlay(
              state: const GameState(phase: GamePhase.driving, lane: 'right'),
              onGasChanged: (_) {},
              onSwitchLane: (_) {},
            ),
          ),
        ),
      );
      final iconColor = IconTheme.of(
        tester.element(find.byIcon(Icons.arrow_forward_rounded)),
      ).color;
      expect(find.text(appL10n.gameRight), findsNothing);
      expect(find.text(appL10n.gameLeft), findsNothing);
      final left = tester.getCenter(find.byIcon(Icons.arrow_back_rounded));
      final right = tester.getCenter(find.byIcon(Icons.arrow_forward_rounded));
      final gas = tester.getCenter(find.byKey(const ValueKey('game-gas')));
      expect(left.dx, lessThan(right.dx));
      expect(right.dx, lessThan(195));
      expect(gas.dx, greaterThan(195));
      expect(tester.takeException(), isNull);
      expect(
        iconColor,
        IconTheme.of(
          tester.element(find.byIcon(Icons.arrow_back_rounded)),
        ).color,
      );
      final press = await tester.startGesture(left);
      await tester.pump();
      expect(
        IconTheme.of(
          tester.element(find.byIcon(Icons.arrow_back_rounded)),
        ).color,
        Colors.white,
      );
      await press.up();
      await tester.pump();
      expect(
        IconTheme.of(
          tester.element(find.byIcon(Icons.arrow_back_rounded)),
        ).color,
        iconColor,
      );
    },
  );

  testWidgets('Compact collision alert and equal control margins', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const state = GameState(
      phase: GamePhase.resolving,
      violationCount: 2,
      lastViolation: 'collision',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const Align(
                alignment: Alignment.topCenter,
                child: GameHud(state: state),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: GameControlsOverlay(
                  state: state,
                  onGasChanged: (_) {},
                  onSwitchLane: (_) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final notice = find.text(appL10n.gameCollision);
    expect(tester.widget<Text>(notice).style!.color, Colors.white);
    final box = tester.widget<Container>(
      find.ancestor(of: notice, matching: find.byType(Container)).first,
    );
    expect(
      (box.decoration as BoxDecoration).color,
      AppColors.of(tester.element(notice)).red,
    );
    final left = find
        .ancestor(
          of: find.byIcon(Icons.arrow_back_rounded),
          matching: find.byType(Material),
        )
        .first;
    final bounds = tester.getRect(left);
    expect(bounds.left, 20);
    expect(844 - bounds.bottom, 20);
    final gas = find.byKey(const ValueKey('game-gas'));
    expect(390 - tester.getRect(gas).right, 20);
    expect(tester.getRect(gas).bottom, bounds.bottom);
    expect(find.text(appL10n.gameResolving), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Countdown and telemetry do not repeatedly stop gas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final platform = _GameWebPlatform();
    WebViewPlatform.instance = platform;
    await tester.pumpWidget(
      ProviderScope(
        overrides: signedIn,
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(390, 640),
              textScaler: TextScaler.linear(1.5),
            ),
            child: GameScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    final engine = platform.controllers.single;
    expect(find.byType(GameControlsOverlay), findsNothing);
    engine.emit('{"event":"ready"}');
    await tester.pump();
    await _startDrive(tester);
    expect(find.byType(GameControlsOverlay), findsOneWidget);
    engine.emit(
      jsonEncode({
        'event': 'approach_situation',
        'situation': {
          'id': 'timer',
          'title': 'Question',
          'options': ['One', 'Two'],
          'correctAnswerIndex': 0,
        },
      }),
    );
    await tester.pump();
    expect(find.byType(GameControlsOverlay), findsNothing);
    final stops = engine.scripts
        .where((s) => s.contains('setGas(false)'))
        .length;
    await tester.pump(const Duration(milliseconds: 500));
    engine.emit('{"event":"telemetry","speedKmH":0,"distanceM":5}');
    await tester.pump();
    expect(
      engine.scripts.where((s) => s.contains('setGas(false)')).length,
      stops,
    );
    await tester.tap(find.text('Two'));
    await tester.pump();
    expect(
      engine.scripts.any((s) => s.contains('releaseTraffic("timer")')),
      true,
    );
    expect(find.byType(GameControlsOverlay), findsNothing);
    await tester.tap(find.text(appL10n.gameContinue));
    await tester.pump();
    expect(find.byType(GameControlsOverlay), findsOneWidget);
    // The answered card slides away before it is gone from the tree.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(GameQuestionCard), findsNothing);
    expect(find.text(appL10n.gameResolving), findsNothing);
    expect(tester.takeException(), isNull);
    engine.emit('{"event":"situation_cleared","situationId":"timer"}');
    await tester.pump();
    expect(find.byType(GameControlsOverlay), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('390px overlays at 1.5 text scale render without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await (FontLoader(
      'Onest',
    )..addFont(rootBundle.load('assets/fonts/Onest-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final situation = GameSituation.fromJson({
      'id': 'render',
      'ticket': 'Билет 20 · Вопрос 14',
      'title': 'Вы намерены повернуть налево. Кому Вы должны уступить дорогу?',
      'explanation': '',
      'pddRule': '13.12',
      'options': [
        'Только встречному автомобилю',
        'Всем транспортным средствам',
        'Никому',
      ],
      'correctAnswerIndex': 1,
      'legend': [
        {'label': 'Ваш автомобиль', 'color': '#ED4621'},
        {'label': 'Встречный автомобиль', 'color': '#0574F8'},
      ],
    });
    final state = GameState(
      phase: GamePhase.situation,
      currentSituation: situation,
      distanceM: 12345,
      score: 123456,
      violationCount: 12,
      oncoming: true,
    );
    final boundary = GlobalKey();
    for (final name in ['question', 'results', 'fuel_results', 'controls']) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Onest'),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(390, 844),
              textScaler: TextScaler.linear(1.5),
              padding: EdgeInsets.only(top: 24, bottom: 20),
            ),
            child: RepaintBoundary(
              key: boundary,
              child: Scaffold(
                backgroundColor: const Color(0xffdee4e5),
                body: name == 'results' || name == 'fuel_results'
                    ? Center(
                        child: GameOverDialog(
                          state: name == 'fuel_results'
                              ? state.copyWith(fuel: 0)
                              : state,
                          fuelRefillAt: name == 'fuel_results'
                              ? DateTime.now().add(const Duration(minutes: 30))
                              : null,
                          bestScore: 3548,
                          onLeaderboard: () {},
                          onBuyPremium: name == 'fuel_results' ? () {} : null,
                          onRestart: () {},
                          onExit: () {},
                        ),
                      )
                    : Stack(
                        children: [
                          Align(
                            alignment: Alignment.topCenter,
                            child: GameHud(state: state),
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (name == 'controls')
                                  GameControlsOverlay(
                                    state: const GameState(
                                      phase: GamePhase.driving,
                                    ),
                                    onGasChanged: (_) {},
                                    onSwitchLane: (_) {},
                                  )
                                else
                                  GameQuestionCard(
                                    state: state,
                                    onSelectAnswer: (_) {},
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: name);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/game_ui/$name-390-scale1.5.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });

  testWidgets('Native ready, theme, failed command, restart and no HUD back', (
    tester,
  ) async {
    final platform = _GameWebPlatform();
    WebViewPlatform.instance = platform;
    var exits = 0;
    Widget screen(Brightness brightness) => ProviderScope(
      overrides: signedIn,
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: GameScreen(onExit: () => exits++),
      ),
    );
    await tester.pumpWidget(screen(Brightness.light));
    await tester.pump();
    final first = platform.controllers.single;
    // The engine must get a mounted viewport BEFORE emitting ready, even
    // though loading the saved vehicle introduced an asynchronous startup.
    expect(find.byType(WebViewWidget), findsOneWidget);
    expect(
      tester.getSize(find.byType(WebViewWidget)).shortestSide,
      greaterThan(0),
    );
    first.emit('{"event":"ready"}');
    await tester.pump();
    await _startDrive(tester);
    expect(
      first.scripts.any(
        (s) =>
            s.contains('configure(') &&
            s.contains('"player"') &&
            s.contains('"soundEnabled"'),
      ),
      true,
    );
    await tester.pumpWidget(screen(Brightness.dark));
    await tester.pumpAndSettle();
    expect(first.scripts.any((s) => s.contains('setTheme(true)')), true);
    first.failCommands = true;
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pump();
    await tester.pump();
    expect(find.text(appL10n.gameLoadError), findsOneWidget);
    await tester.tap(find.text(appL10n.gameRestart));
    await tester.pump();
    await tester.pump();
    expect(platform.controllers.length, 2);
    first.emit('{"event":"ready"}');
    expect(find.text(appL10n.gameLoading), findsOneWidget);
    platform.controllers.last.emit('{"event":"ready"}');
    await tester.pump();
    await _startDrive(tester);
    expect(
      find.descendant(
        of: find.byType(GameHud),
        matching: find.byIcon(Icons.arrow_back_rounded),
      ),
      findsNothing,
    );
    expect(exits, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Native main document loading failure is recoverable', (
    tester,
  ) async {
    final platform = _GameWebPlatform();
    WebViewPlatform.instance = platform;
    await tester.pumpWidget(
      ProviderScope(
        overrides: signedIn,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();
    platform.controllers.single.navigation.error!(
      WebResourceError(
        errorCode: -1,
        description: 'failed',
        isForMainFrame: true,
      ),
    );
    await tester.pump();
    expect(find.text(appL10n.gameLoadError), findsOneWidget);
    expect(find.text(appL10n.gameRestart), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final ready in [false, true]) {
    testWidgets(
      'Engine error recovers with ready=$ready and ignores old session',
      (tester) async {
        final platform = _GameWebPlatform();
        WebViewPlatform.instance = platform;
        await tester.pumpWidget(
          ProviderScope(
            overrides: signedIn,
            child: const MaterialApp(home: GameScreen()),
          ),
        );
        await tester.pump();
        final old = platform.controllers.single;
        if (ready) old.emit('{"event":"ready"}');
        old.emit(
          '{"event":"engine_error","message":"ReferenceError: THREE is not defined"}',
        );
        await tester.pump();
        expect(find.text(appL10n.gameLoadError), findsOneWidget);
        await tester.tap(find.text(appL10n.gameRestart));
        await tester.pump();
        old.emit('{"event":"engine_error"}');
        platform.controllers.last.emit('{"event":"ready"}');
        await tester.pump(const Duration(seconds: 31));
        await _startDrive(tester);
        expect(find.text(appL10n.gameLoadError), findsNothing);
        expect(find.byType(GameControlsOverlay), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('Readiness timeout counts foreground time and offers restart', (
    tester,
  ) async {
    WebViewPlatform.instance = _GameWebPlatform();
    await tester.pumpWidget(
      ProviderScope(
        overrides: signedIn,
        child: const MaterialApp(home: GameScreen()),
      ),
    );
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 40));
    expect(find.text(appL10n.gameLoadError), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 29));
    expect(find.text(appL10n.gameLoadError), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(appL10n.gameLoadError), findsOneWidget);
    expect(find.text(appL10n.gameRestart), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  group('GameSituation Model Tests', () {
    test('Correctly deserializes from JSON', () {
      final json = {
        'id': 'ticket_1_14',
        'ticket': 'Билет 1 · Вопрос 14',
        'type': 'crossroad_tram',
        'title': 'Кому уступить дорогу?',
        'explanation': 'Трамвай имеет преимущество.',
        'pddRule': 'п. 13.11',
        'options': ['Обоим трамваям', 'Только трамваю А'],
        'correctAnswerIndex': 0,
        'legend': [
          {'label': 'Вы прямо', 'color': '#ED4621'},
          {'label': 'Трамвай А', 'color': '#0574F8'},
        ],
      };

      final sit = GameSituation.fromJson(json);

      expect(sit.id, 'ticket_1_14');
      expect(sit.ticket, 'Билет 1 · Вопрос 14');
      expect(sit.type, 'crossroad_tram');
      expect(sit.options.length, 2);
      expect(sit.correctAnswerIndex, 0);
      expect(sit.legend.length, 2);
      expect(sit.legend[0].label, 'Вы прямо');
      expect(sit.legend[0].color, '#ED4621');
    });
  });

  group('GameController Lifecycle Tests', () {
    late GameController controller;

    final dummySituation = GameSituation.fromJson(const {
      'id': 'test_sit',
      'ticket': 'Билет 1 · Вопрос 1',
      'type': 'crossroad',
      'title': 'Тестовый вопрос',
      'explanation': 'Правило ПДД тест',
      'pddRule': 'п. 1.1',
      'options': ['Ответ 1', 'Ответ 2', 'Ответ 3'],
      'correctAnswerIndex': 1,
      'legend': [],
    });

    setUp(() {
      controller = GameController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('Initial state is ready and defaults are valid', () {
      expect(controller.state.phase, GamePhase.ready);
      expect(controller.state.fuel, 5);
      expect(controller.state.score, 0);
      expect(controller.state.distanceM, 0);
    });

    test('Engine ready transitions to driving phase', () {
      controller.onEngineReady();
      expect(controller.state.phase, GamePhase.driving);
    });

    test(
      'Approaching situation transitions to situation phase and starts countdown',
      () {
        controller.onEngineReady();
        controller.onApproachSituation(dummySituation);

        expect(controller.state.phase, GamePhase.situation);
        expect(controller.state.currentSituation, dummySituation);
        expect(controller.state.remainingSeconds, 15.0);
      },
    );

    test(
      'Correct answer updates score, streak, and transitions to resolving',
      () {
        bool engineNotified = false;
        bool engineVerdict = false;
        controller.onSituationResolvedToEngine = (isCorrect, id) {
          expect(id, dummySituation.id);
          engineNotified = true;
          engineVerdict = isCorrect;
        };

        controller.onEngineReady();
        controller.onApproachSituation(dummySituation);

        controller.submitAnswer(1); // Correct index is 1

        expect(controller.state.phase, GamePhase.resolving);
        expect(controller.state.isLastAnswerCorrect, true);
        expect(controller.state.consecutiveCorrect, 1);
        expect(controller.state.totalCorrect, 1);
        expect(controller.state.score, greaterThan(0));
        expect(engineNotified, true);
        expect(engineVerdict, true);
      },
    );

    test('Incorrect answer loses a life and shows explanation', () {
      bool engineNotified = false;
      controller.onSituationResolvedToEngine = (_, id) {
        engineNotified = true;
      };

      controller.onEngineReady();
      controller.onApproachSituation(dummySituation);

      controller.submitAnswer(0); // Wrong index

      expect(controller.state.phase, GamePhase.explanation);
      expect(controller.state.isLastAnswerCorrect, false);
      expect(controller.state.consecutiveCorrect, 0);
      expect(controller.state.fuel, 4);
      expect(controller.state.totalMistakes, 1);
      // Engine is not yet notified until user taps continue
      expect(engineNotified, false);

      controller.continueAfterExplanation();
      expect(controller.state.phase, GamePhase.resolving);
      expect(engineNotified, true);
    });

    test('Burning the last fuel unit triggers gameOver phase', () {
      controller.onEngineReady();
      controller.configureFuel(fuel: 3, unlimited: false);

      // Mistake 1
      controller.onApproachSituation(dummySituation);
      controller.submitAnswer(0);
      expect(controller.state.fuel, 2);
      controller.continueAfterExplanation();

      // Mistake 2
      controller.onSituationClearedFromEngine(dummySituation.id);
      controller.onApproachSituation(
        GameSituation.fromJson({...dummySituation.toJson(), 'id': 'second'}),
      );
      controller.submitAnswer(0);
      expect(controller.state.fuel, 1);
      controller.continueAfterExplanation();

      // Mistake 3 -> Game Over
      controller.onSituationClearedFromEngine('second');
      controller.onApproachSituation(
        GameSituation.fromJson({...dummySituation.toJson(), 'id': 'third'}),
      );
      controller.submitAnswer(0);
      expect(controller.state.fuel, 0);
      expect(controller.state.phase, GamePhase.gameOver);
    });

    test('Unlimited fuel is not spent on mistakes', () {
      controller.onEngineReady();
      controller.configureFuel(fuel: 0, unlimited: true);
      controller.onApproachSituation(dummySituation);
      controller.submitAnswer(0);

      expect(controller.state.fuelUnlimited, isTrue);
      expect(controller.state.fuel, GameState.maxFuel);
      expect(controller.state.phase, GamePhase.explanation);
    });

    test('Telemetry updates distance, speed and score', () {
      controller.onEngineReady();
      controller.updateTelemetry(speedKmH: 42, distanceM: 250);

      expect(controller.state.speedKmH, 42);
      expect(controller.state.distanceM, 250);
      expect(controller.state.score, 125);
    });

    test(
      'Telemetry preserves streak bonus and rejects distance regression',
      () {
        controller.onEngineReady();
        controller.updateTelemetry(speedKmH: 20, distanceM: 100);
        controller.onApproachSituation(dummySituation);
        controller.submitAnswer(1);
        controller.updateTelemetry(speedKmH: 20, distanceM: 102);
        expect(controller.state.score, 176);
        controller.updateTelemetry(speedKmH: 20, distanceM: 0);
        expect(controller.state.score, 176);
      },
    );

    test(
      'Duplicate approach, invalid answers and stale clear cannot advance',
      () {
        controller.onEngineReady();
        controller.onApproachSituation(dummySituation);
        controller.submitAnswer(-1);
        expect(controller.state.totalAnswered, 0);
        controller.onSituationClearedFromEngine(dummySituation.id);
        expect(controller.state.phase, GamePhase.situation);
        controller.submitAnswer(1);
        controller.onApproachSituation(dummySituation);
        controller.onSituationClearedFromEngine('stale');
        expect(controller.state.phase, GamePhase.resolving);
        controller.onSituationClearedFromEngine(dummySituation.id);
        controller.onApproachSituation(dummySituation);
        expect(controller.state.phase, GamePhase.driving);
      },
    );

    test(
      'Oncoming episodes count once without burning fuel; restart clears all',
      () {
        controller.onEngineReady();
        final oldSession = controller.sessionId;
        controller.updateLane('left', true);
        controller.recordViolation('oncoming', 1);
        controller.recordViolation('oncoming', 1);
        controller.recordViolation('oncoming', 2);
        expect(controller.state.violationCount, 2);
        expect(controller.state.fuel, 5);
        expect(controller.state.totalMistakes, 0);
        controller.restartGame();
        expect(controller.acceptsSession(oldSession), false);
        expect(controller.acceptsSession(null), false);
        expect(controller.state.violationCount, 0);
        expect(controller.state.oncoming, false);
        expect(controller.state.phase, GamePhase.ready);
      },
    );

    testWidgets('Pause freezes answer countdown and releases gas', (
      tester,
    ) async {
      var stops = 0;
      final released = <String>[];
      controller.onTrafficReleaseToEngine = released.add;
      controller.onStopGas = () => stops++;
      controller.onEngineReady();
      controller.onApproachSituation(dummySituation);
      controller.setPaused(true);
      await tester.pump(const Duration(seconds: 20));
      expect(controller.state.remainingSeconds, 15);
      expect(controller.state.fuel, 5);
      expect(stops, 2);
      controller.setPaused(false);
      await tester.pump(const Duration(seconds: 16));
      expect(controller.state.fuel, 4);
      expect(controller.state.phase, GamePhase.explanation);
      expect(released, [dummySituation.id]);
    });

    testWidgets('Situation controls cannot accelerate or change lanes', (
      tester,
    ) async {
      final gas = <bool>[];
      final lanes = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameControlsOverlay(
              state: const GameState(phase: GamePhase.situation),
              onGasChanged: gas.add,
              onSwitchLane: lanes.add,
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
      await tester.tap(find.byKey(const ValueKey('game-gas')));
      expect(gas, isEmpty);
      expect(lanes, isEmpty);
    });

    test('Only verified country has game enabled', () {
      expect(CountryConfig.russia.hasVerifiedGame, true);
      expect(CountryConfig.belarus.hasVerifiedGame, false);
      expect(CountryConfig.serbia.hasVerifiedGame, false);
    });

    test('Curated scenarios can repeat after another completed situation', () {
      controller.onEngineReady();
      controller.onApproachSituation(dummySituation);
      controller.submitAnswer(1);
      controller.onSituationClearedFromEngine(dummySituation.id);
      final second = GameSituation.fromJson({
        ...dummySituation.toJson(),
        'id': 'second',
      });
      controller.onApproachSituation(second);
      controller.submitAnswer(1);
      controller.onSituationClearedFromEngine(second.id);
      controller.onApproachSituation(dummySituation);
      expect(controller.state.phase, GamePhase.situation);
      expect(controller.state.currentSituation?.id, dummySituation.id);
    });

    testWidgets('Held gas releases when controls become disabled', (
      tester,
    ) async {
      final gas = <bool>[];
      Widget controls(GamePhase phase) => MaterialApp(
        home: Scaffold(
          body: GameControlsOverlay(
            state: GameState(phase: phase),
            onGasChanged: gas.add,
            onSwitchLane: (_) {},
          ),
        ),
      );
      await tester.pumpWidget(controls(GamePhase.driving));
      final press = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('game-gas'))),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(gas, [true]);
      await tester.pumpWidget(controls(GamePhase.situation));
      expect(gas, [true, false]);
      await press.up();
    });

    testWidgets(
      'Gas survives finger drift, telemetry rebuild and second-finger steering',
      (tester) async {
        final gas = <bool>[];
        final steering = <int>[];
        Widget controls(int speed) => MaterialApp(
          home: Scaffold(
            body: GameControlsOverlay(
              state: GameState(phase: GamePhase.resolving, speedKmH: speed),
              onGasChanged: gas.add,
              onSwitchLane: (_) {},
              onSteering: steering.add,
            ),
          ),
        );
        await tester.pumpWidget(controls(0));
        final pedal = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('game-gas'))),
          pointer: 1,
        );
        await pedal.moveBy(const Offset(-40, -35));
        await tester.pumpWidget(controls(20));
        final wheel = await tester.startGesture(
          tester.getCenter(find.byIcon(Icons.arrow_back_rounded)),
          pointer: 2,
        );
        await tester.pump(const Duration(seconds: 2));
        expect(gas, [true]);
        expect(steering, [1]);
        await wheel.up();
        expect(steering, [1, 0]);
        expect(gas, [true]);
        await pedal.up();
        expect(gas, [true, false]);
      },
    );

    testWidgets('Oncoming warning remains across phases on a narrow screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final phase in [
        GamePhase.driving,
        GamePhase.situation,
        GamePhase.resolving,
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GameHud(
                state: GameState(
                  phase: phase,
                  oncoming: true,
                  violationCount: 2,
                  distanceM: 12345,
                  score: 123456,
                ),
              ),
            ),
          ),
        );
        expect(find.text(appL10n.gameOncoming), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
        expect(find.byKey(const ValueKey('hud-hud_warning')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });
}

class _GameWebPlatform extends WebViewPlatform {
  final controllers = <_GameWebController>[];
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = _GameWebController(params);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _GameNavigation(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _GameWebWidget(params);
}

class _GameNavigation extends PlatformNavigationDelegate {
  _GameNavigation(super.params) : super.implementation();
  WebResourceErrorCallback? error;
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {
    error = callback;
  }
}

class _GameWebController extends PlatformWebViewController {
  _GameWebController(super.params) : super.implementation();
  final scripts = <String>[];
  bool channelRemoved = false;
  Completer<void>? detachGate;
  bool failCommands = false;
  late JavaScriptChannelParams channel;
  late _GameNavigation navigation;
  void emit(String message) =>
      channel.onMessageReceived(JavaScriptMessage(message: message));
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    navigation = handler as _GameNavigation;
  }

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    channel = params;
  }

  @override
  Future<void> loadFlutterAsset(String key) async {}
  @override
  Future<void> removeJavaScriptChannel(String name) async {
    expect(scripts[scripts.length - 3], 'window.game?.setGas?.(false);');
    expect(scripts[scripts.length - 2], 'window.game?.setBrake?.(false);');
    expect(scripts.last, 'window.game?.setPaused?.(true);');
    await detachGate?.future;
    channelRemoved = true;
  }

  @override
  Future<void> runJavaScript(String script) async {
    scripts.add(script);
    if (failCommands) throw StateError('bridge failed');
  }
}

class _GameWebWidget extends PlatformWebViewWidget {
  _GameWebWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

/// The game opens on the garage start screen: tap «Start the drive» when it
/// is shown (a restarted run goes straight to driving).
Future<void> _startDrive(WidgetTester tester) async {
  final start = find.text(appL10n.gameLobbyStart);
  if (start.evaluate().isEmpty) return;
  await tester.tap(start, warnIfMissed: false);
  await tester.pump();
}
