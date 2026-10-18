import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/core/config/store_config.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/game_garage_service.dart';
import 'package:pdd_app/data/services/game_question_history_service.dart';
import 'package:pdd_app/data/services/progress_sync_service.dart';
import 'package:pdd_app/data/services/review_prompt_service.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_over_dialog.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/game/godot_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pdd/godot_game');
  final garage = GameGarageService.instance;
  late ProgressDataSource progress;
  late List<List<String>> launches;
  late BuildContext gameContext;
  late WidgetRef gameRef;
  String? nativeResponse;
  Completer<String?>? nativePending;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    GodotGame.resetForTest();
    ProgressSyncService.instance.cancel();
    progress = ProgressDataSource();
    await progress.init();
    launches = [];
    nativeResponse = null;
    nativePending = null;
    HapticFeedbackHelper.setEnabled(false);
    SoundEffectsService.instance.setEnabled(false);
    updateAppLocale(const Locale('ru'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'start') return true;
          launches.add(
            List<String>.from((call.arguments as Map)['args'] as List),
          );
          return nativePending?.future ?? nativeResponse;
        });
  });

  tearDown(() {
    ProgressSyncService.instance.cancel();
    HapticFeedbackHelper.setEnabled(true);
    SoundEffectsService.instance.setEnabled(true);
    debugDefaultTargetPlatformOverride = null;
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearPlatformBrightnessTestValue();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> open(
    WidgetTester tester, {
    bool premium = false,
    Locale locale = const Locale('ru'),
    ThemeMode themeMode = ThemeMode.system,
    ReviewPromptService? review,
  }) async {
    garage.resetForTest();
    updateAppLocale(locale);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          progressDataSourceProvider.overrideWithValue(progress),
          isPremiumProvider.overrideWithValue(premium),
          if (review != null)
            reviewPromptServiceProvider.overrideWithValue(review),
        ],
        child: MaterialApp(
          locale: locale,
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: themeMode,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                gameContext = context;
                gameRef = ref;
                return Column(
                  children: [
                    TextButton(
                      onPressed: () => GodotGame.play(context, ref),
                      child: const Text('City'),
                    ),
                    TextButton(
                      onPressed: () => GodotGame.playRegulator(context, ref),
                      child: const Text('Regulator'),
                    ),
                    TextButton(
                      onPressed: () => GodotGame.playCrossroads(context, ref),
                      child: const Text('Crossroads'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> launch(WidgetTester tester, [String label = 'City']) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
    expect(tester.takeException(), isNull);
  }

  Map<String, dynamic> options() => Map<String, dynamic>.from(
    jsonDecode(
          launches.last
              .singleWhere((arg) => arg.startsWith('--ride-options='))
              .substring('--ride-options='.length),
        )
        as Map,
  );

  List<String> paints(Map car) => [
    for (final paint in (car['paints'] as List).cast<Map>())
      paint['paint'] as String,
  ];

  String citySummary(int correct, {bool resumed = false}) => jsonEncode({
    'run_started': true,
    'finished': false,
    'resumed': resumed,
    'answered': correct,
    'correct': correct,
    'score': correct * 10,
    'car': {'id': 'hatch', 'paint': 'red'},
  });

  Future<void> pumpUntilLaunched(WidgetTester tester, int count) async {
    for (var attempt = 0; attempt < 20 && launches.length < count; attempt++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(launches, hasLength(count));
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
      'native report validation replies on $platform without ending the ride',
      (tester) async {
        await open(tester, premium: true);
        debugDefaultTargetPlatformOverride = platform;
        nativePending = Completer<String?>();
        final ride = GodotGame.play(gameContext, gameRef);
        await pumpUntilLaunched(tester, 1);
        const codec = StandardMethodCodec();
        final reply = Completer<Object?>();
        tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          channel.name,
          codec.encodeMethodCall(
            const MethodCall(
              'reportQuestion',
              '{"question_id":8,"message":"bug"}',
            ),
          ),
          (bytes) => reply.complete(codec.decodeEnvelope(bytes!)),
        );
        await tester.pumpAndSettle();
        expect(reply.isCompleted, isTrue);
        expect(await reply.future, isFalse);
        expect(nativePending!.isCompleted, isFalse);
        expect(launches, hasLength(1));
        nativePending!.complete(null);
        await tester.pumpAndSettle();
        await ride;
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'all games follow the selected app theme on $platform on every launch',
      (tester) async {
        for (final brightness in [
          Brightness.light,
          Brightness.dark,
          Brightness.light,
        ]) {
          tester.binding.platformDispatcher.platformBrightnessTestValue =
              brightness == Brightness.light
              ? Brightness.dark
              : Brightness.light;
          await open(
            tester,
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
          );
          for (final game in ['City', 'Regulator', 'Crossroads']) {
            debugDefaultTargetPlatformOverride = platform;
            await tester.tap(find.text(game));
            await tester.pumpAndSettle();
            debugDefaultTargetPlatformOverride = null;
            expect(
              launches.last.where((arg) => arg == '--dark' || arg == '--light'),
              [brightness == Brightness.dark ? '--dark' : '--light'],
              reason: '$game must receive the app theme when the OS disagrees',
            );
            expect(tester.takeException(), isNull);
          }
        }
      },
    );
  }

  for (final firstGame in ['City', 'Regulator', 'Crossroads']) {
    testWidgets('$firstGame reserves preparation and native startup once', (
      tester,
    ) async {
      await open(tester, premium: true);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      nativePending = Completer<String?>();
      final first = switch (firstGame) {
        'City' => GodotGame.play(gameContext, gameRef),
        'Regulator' => GodotGame.playRegulator(gameContext, gameRef),
        _ => GodotGame.playCrossroads(gameContext, gameRef),
      };
      // These calls arrive before even the preparation overlay's first frame.
      await GodotGame.play(gameContext, gameRef);
      await GodotGame.playRegulator(gameContext, gameRef);
      await GodotGame.playCrossroads(gameContext, gameRef);
      await pumpUntilLaunched(tester, 1);
      // A second game is still rejected while the first native result is pending.
      await GodotGame.playCrossroads(gameContext, gameRef);
      expect(launches, hasLength(1));
      nativePending!.complete(null);
      await tester.pumpAndSettle();
      await first;

      nativePending = null;
      await tester.tap(find.text('Regulator'));
      await tester.pumpAndSettle();
      expect(launches, hasLength(2));
      debugDefaultTargetPlatformOverride = null;
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Back before preparation does not read a disposed ref or start a game',
    (tester) async {
      await open(tester, premium: true);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final navigator = Navigator.of(gameContext);
      navigator.push<void>(
        PageRouteBuilder<void>(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                gameContext = context;
                gameRef = ref;
                return const Text('Temporary games page');
              },
            ),
          ),
        ),
      );
      await tester.pump();
      final first = GodotGame.play(gameContext, gameRef);
      navigator.pop();
      await tester.pump();
      await tester.pump();
      await first;
      expect(launches, isEmpty);
      expect(find.text('Temporary games page'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Regulator'));
      await tester.pumpAndSettle();
      expect(launches, hasLength(1));
      debugDefaultTargetPlatformOverride = null;
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native city visit books completed replays and the unfinished last run',
    (tester) async {
      await open(tester, premium: true);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      nativeResponse = jsonEncode({
        'native_result': true,
        'run_started': true,
        'finished': false,
        'answered': 2,
        'correct': 2,
        'score': 20,
        'city_runs': [
          {
            'native_result': true,
            'run_started': true,
            'finished': true,
            'answered': 20,
            'correct': 3,
            'score': 120,
          },
          {
            'native_result': true,
            'run_started': true,
            'finished': true,
            'answered': 20,
            'correct': 4,
            'score': 160,
          },
        ],
      });
      await tester.tap(find.text('City'));
      await tester.pumpAndSettle();
      expect(find.byType(GameOverDialog), findsNothing);
      expect(progress.getGameBestScore(), 160);
      expect(garage.correctTotal, 9);
      final prefs = await SharedPreferences.getInstance();
      final pending = jsonDecode(prefs.getString('game_run_pending')!);
      expect(pending['score'], 20);
      expect(pending['correct'], 2);
      nativeResponse = null;
      await tester.tap(find.text('City'));
      await tester.pumpAndSettle();
      expect(launches, hasLength(2));
      expect(options()['resume']['score'], 20);
      debugDefaultTargetPlatformOverride = null;
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'result restart reserves a new run while the old dialog completes',
    (tester) async {
      await open(tester, premium: true);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      nativeResponse = jsonEncode({
        'run_started': true,
        'finished': true,
        'answered': 20,
        'correct': 0,
        'score': 0,
      });
      await tester.tap(find.text('City'));
      await tester.pumpAndSettle();
      expect(find.text(appL10n.gameRestart), findsOneWidget);
      nativePending = Completer<String?>();
      await tester.tap(find.text(appL10n.gameRestart));
      await pumpUntilLaunched(tester, 2);
      await GodotGame.playRegulator(gameContext, gameRef);
      expect(launches, hasLength(2));
      nativePending!.complete(null);
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
      expect(tester.takeException(), isNull);
    },
  );

  for (final (platform, store) in [
    (TargetPlatform.android, AppStore.googlePlay),
    (TargetPlatform.iOS, AppStore.googlePlay),
    (TargetPlatform.android, AppStore.rustore),
  ]) {
    for (final behavior in ['dismiss', 'throw', 'hang']) {
      testWidgets(
        'city preserves saved results after review $behavior on $platform/$store',
        (tester) async {
          final request = Completer<void>();
          var requests = 0;
          int? savedScoreAtRequest;
          bool? hadResultAtRequest;
          final review = ReviewPromptService.forTesting(
            platform: platform,
            store: store,
            isAvailable: () async => true,
            requestReview: () {
              requests++;
              // Bookkeeping must finish before the native prompt starts.
              hadResultAtRequest = find
                  .byType(GameOverDialog)
                  .evaluate()
                  .isNotEmpty;
              savedScoreAtRequest = progress.getGameBestScore();
              if (behavior == 'throw') {
                throw PlatformException(code: 'unavailable');
              }
              return request.future;
            },
          );
          await open(tester, premium: true, review: review);
          debugDefaultTargetPlatformOverride = platform;
          nativeResponse = jsonEncode({
            'run_started': true,
            'finished': true,
            'answered': 20,
            'correct': 5,
            'score': 50,
            'mistakes': ['ticket_10_13'],
          });
          await tester.tap(find.text('City'));
          await tester.pumpAndSettle();
          expect(requests, 1);
          expect(hadResultAtRequest, isFalse);
          expect(savedScoreAtRequest, 50);
          if (behavior != 'throw') {
            expect(find.byType(GameOverDialog), findsNothing);
            // The launching menu must not start a second game behind the prompt.
            await GodotGame.playRegulator(gameContext, gameRef);
            expect(launches, hasLength(1));
            if (behavior == 'dismiss') {
              request.complete();
            } else {
              await tester.pump(const Duration(seconds: 3));
            }
            await tester.pumpAndSettle();
          }
          final result = tester.widget<GameOverDialog>(
            find.byType(GameOverDialog),
          );
          expect(result.state.score, 50);
          expect(result.state.totalAnswered, 20);
          expect(result.state.totalCorrect, 5);
          expect(result.state.mistakes.single.id, 'ticket_10_13');
          expect(progress.getGameBestScore(), 50);
          if (!request.isCompleted) request.complete();
          await tester.pumpAndSettle();
          expect(find.byType(GameOverDialog), findsOneWidget);
          expect(requests, 1);
          debugDefaultTargetPlatformOverride = null;
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('partial city ride never consumes a completion milestone', (
    tester,
  ) async {
    var requests = 0;
    final review = ReviewPromptService.forTesting(
      platform: TargetPlatform.android,
      isAvailable: () async => true,
      requestReview: () async {
        requests++;
      },
    );
    await open(tester, premium: true, review: review);
    nativeResponse = citySummary(3);
    await launch(tester);
    expect(requests, 0);
    await review.onCompleted();
    expect(requests, 1);
  });

  testWidgets('city history persists after its launching route is disposed', (
    tester,
  ) async {
    await open(tester, premium: true);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    nativePending = Completer<String?>();
    final first = GodotGame.play(gameContext, gameRef);
    await pumpUntilLaunched(tester, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    final history = {
      'version': 1,
      'sequence': 3,
      'last_shown': {'ticket_10_13': 3},
      'show_counts': {'ticket_10_13': 2},
    };
    nativePending!.complete(jsonEncode({'question_history': history}));
    await tester.pump();
    await first;
    final prefs = await SharedPreferences.getInstance();
    expect(
      jsonDecode(prefs.getString(GameQuestionHistoryService.storageKey)!),
      history,
    );
    debugDefaultTargetPlatformOverride = null;
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'shown city history survives exit before any answer on Android and iOS',
    (tester) async {
      await open(tester);
      final history = {
        'version': 1,
        'sequence': 4,
        'last_shown': {'ticket_19_13': 4, 'ticket_29_14': 2},
        'show_counts': {'ticket_19_13': 3, 'ticket_29_14': 1},
      };
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        nativeResponse = jsonEncode({
          'run_started': false,
          'answered': 0,
          'question_history': history,
        });
        debugDefaultTargetPlatformOverride = platform;
        await tester.tap(find.text('City'));
        await tester.pumpAndSettle();
        // A fresh Dart bridge/session must recover history from local preferences.
        GodotGame.resetForTest();
        nativeResponse = null;
        await tester.tap(find.text('City'));
        await tester.pumpAndSettle();
        expect(options()['question_history'], history);
        expect(tester.takeException(), isNull);
      }
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('notification previews are available only in a debug city ride', (
    tester,
  ) async {
    await open(tester);
    await launch(tester);

    const gameDebug = bool.fromEnvironment('GAME_DEBUG');
    expect(launches.last.contains('--debug-menu'), gameDebug);
    expect(launches.last, isNot(contains('--perf')));
    expect(options().containsKey('debug_perf'), gameDebug);
    if (gameDebug) expect(options()['debug_perf'], isFalse);

    for (final game in ['Regulator', 'Crossroads']) {
      await launch(tester, game);
      expect(launches.last, isNot(contains('--debug-menu')));
      expect(launches.last, isNot(contains('--perf')));
    }
  });

  testWidgets('city performance overlay choice persists only in dev builds', (
    tester,
  ) async {
    const gameDebug = bool.fromEnvironment('GAME_DEBUG');
    final prefs = await SharedPreferences.getInstance();
    await open(tester);

    nativeResponse = jsonEncode({'run_started': false, 'debug_perf': true});
    await launch(tester);
    expect(prefs.getBool('godot_city_perf'), gameDebug ? isTrue : isNull);

    nativeResponse = null;
    await launch(tester);
    expect(launches.last.contains('--perf'), gameDebug);
    expect(options().containsKey('debug_perf'), gameDebug);
    if (gameDebug) expect(options()['debug_perf'], isTrue);

    nativeResponse = jsonEncode({'run_started': false, 'debug_perf': false});
    await launch(tester);
    expect(prefs.getBool('godot_city_perf'), gameDebug ? isFalse : isNull);

    nativeResponse = null;
    await launch(tester);
    expect(launches.last, isNot(contains('--perf')));
    if (gameDebug) expect(options()['debug_perf'], isFalse);
  });

  testWidgets('saved diagnostics stay hidden in production and mini-games', (
    tester,
  ) async {
    const gameDebug = bool.fromEnvironment('GAME_DEBUG');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('godot_city_perf', true);
    await open(tester);
    await launch(tester);
    expect(launches.last.contains('--perf'), gameDebug);
    expect(options().containsKey('debug_perf'), gameDebug);
    if (gameDebug) expect(options()['debug_perf'], isTrue);

    for (final game in ['Regulator', 'Crossroads']) {
      await launch(tester, game);
      expect(launches.last, isNot(contains('--perf')));
    }

    nativeResponse = jsonEncode({'run_started': false, 'debug_perf': false});
    await launch(tester);
    expect(prefs.getBool('godot_city_perf'), gameDebug ? isFalse : isTrue);
  });

  testWidgets('malformed diagnostics summaries preserve the saved choice', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('godot_city_perf', true);
    await open(tester);
    for (final value in ['false', 0, null]) {
      nativeResponse = jsonEncode({'run_started': false, 'debug_perf': value});
      await launch(tester);
      expect(prefs.getBool('godot_city_perf'), isTrue);
    }
  });

  testWidgets('all earned colours are identical for every owned model', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('game_garage_correct', 420);
    await prefs.setString('game_vehicle', 'pickup');
    await prefs.setString('game_vehicle_paint', 'gold');
    await open(tester);
    await launch(tester);

    final ride = options();
    final cars = (ride['cars'] as List).cast<Map>();
    expect(cars.map((car) => car['id']), GameGarageService.models);
    for (final car in cars) {
      expect(paints(car), GameGarageService.paints);
    }
    expect(ride['selected'], {'id': 'pickup', 'paint': 'yellow'});
    expect(prefs.getString('game_vehicle_paint'), 'yellow');
    expect((ride['achievement'] as Map)['complete'], isTrue);
    expect((ride['reward_list'] as List).length, 10);
    expect((ride['reward_paints'] as List).length, 6);
  });

  testWidgets('legacy per-car paints become a single shared palette', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'game_garage_cars',
      jsonEncode([
        {'id': 'hatch', 'paint': 'red'},
        {'id': 'sedan', 'paint': 'blue'},
        {'id': 'pickup', 'paint': 'teal'},
      ]),
    );
    await open(tester);
    await launch(tester);

    final cars = (options()['cars'] as List).cast<Map>();
    expect(cars.map((car) => car['id']), ['hatch', 'sedan', 'pickup']);
    for (final car in cars) {
      expect(paints(car), ['red', 'blue', 'green']);
    }
  });

  testWidgets('premium has all seven models and the same eight colours', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('game_vehicle', 'cyber');
    await prefs.setString('game_vehicle_paint', 'purple');
    await open(tester, premium: true);
    await launch(tester);

    final ride = options();
    final cars = (ride['cars'] as List).cast<Map>();
    expect(cars.length, 7);
    expect(cars.last['id'], 'cyber');
    for (final car in cars) {
      expect(paints(car), GameGarageService.paints);
    }
    expect(ride['selected'], {'id': 'cyber', 'paint': 'red'});
    expect(ride['garage_premium'], isTrue);
  });

  testWidgets('expired premium restores an owned model and colour', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('game_vehicle', 'cyber');
    await prefs.setString('game_vehicle_paint', 'gold');
    await open(tester);
    await launch(tester);

    expect(options()['selected'], {'id': 'hatch', 'paint': 'red'});
    expect(prefs.getString('game_vehicle'), 'hatch');
    expect(prefs.getString('game_vehicle_paint'), 'red');
  });

  testWidgets(
    'only city correct answers count and resumed answers count once',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('game_vehicle_paint', 'gold');
      await open(tester);
      nativeResponse = jsonEncode({'solved': 30, 'score': 90, 'wrong': 0});
      await launch(tester, 'Regulator');
      expect(launches.last, contains('--paint=#E8C547'));
      await launch(tester, 'Crossroads');
      expect(launches.last, contains('--paint=#E8C547'));
      expect(prefs.getInt('game_garage_correct'), isNull);

      nativeResponse = citySummary(3);
      await launch(tester);
      expect(garage.correctTotal, 3);
      expect(prefs.getInt('game_runs'), 2);
      nativeResponse = citySummary(4, resumed: true);
      await launch(tester);
      expect(garage.correctTotal, 4);
      await launch(tester);
      expect(garage.correctTotal, 4);
      expect(prefs.getInt('game_garage_correct'), 4);
      expect(prefs.getInt('game_runs'), 2);
      expect(
        (jsonDecode(prefs.getString('game_run_pending')!) as Map)['correct'],
        4,
      );
    },
  );

  testWidgets(
    'premium correct answers earn permanent rewards without dialogs',
    (tester) async {
      await open(tester, premium: true);
      nativeResponse = citySummary(11);
      await launch(tester);
      final prefs = await SharedPreferences.getInstance();
      expect(garage.correctTotal, 11);
      expect(prefs.getInt('game_garage_correct'), 11);
      expect(garage.owns('sedan', 'blue'), isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      expect(prefs.getInt('game_runs'), isNull);
    },
  );

  testWidgets(
    'new colour is global and pending answers are saved before reveal',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('game_garage_correct', 9);
      await prefs.setString('game_vehicle', 'sedan');
      await prefs.setString('game_vehicle_paint', 'red');
      await open(tester);
      nativeResponse = jsonEncode({
        'run_started': true,
        'finished': false,
        'answered': 1,
        'correct': 1,
        'score': 10,
        'car': {'id': 'sedan', 'paint': 'red'},
      });
      await launch(tester);

      expect(find.text(appL10n.gameRevealPaintTitle), findsOneWidget);
      expect(
        find.text(appL10n.gameRevealPaintBody(appL10n.gamePaintBlue)),
        findsOneWidget,
      );
      expect(
        (jsonDecode(prefs.getString('game_run_pending')!) as Map)['correct'],
        1,
      );
      expect(garage.owns('hatch', 'blue'), isTrue);
      expect(garage.owns('sedan', 'blue'), isTrue);
      await tester.tap(find.text(appL10n.gameRevealChoose));
      await tester.pumpAndSettle();
      expect(prefs.getString('game_vehicle'), 'sedan');
      expect(prefs.getString('game_vehicle_paint'), 'blue');
    },
  );

  for (final reward in {'model:sedan': 4, 'paint:blue': 9}.entries) {
    testWidgets(
      '${reward.key} shown in Godot is saved without a duplicate reveal',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('game_garage_correct', reward.value);
        await open(tester);
        nativeResponse = jsonEncode({
          'run_started': true,
          'finished': false,
          'answered': 1,
          'correct': 1,
          'score': 10,
          'notified_rewards': [reward.key],
        });
        await launch(tester);

        expect(find.byType(AlertDialog), findsNothing);
        expect(garage.correctTotal, reward.value + 1);
        expect(prefs.getInt('game_garage_correct'), reward.value + 1);
        expect(
          garage.owns('sedan', reward.key == 'paint:blue' ? 'blue' : 'red'),
          isTrue,
        );
        expect(
          (jsonDecode(prefs.getString('game_run_pending')!) as Map)['correct'],
          1,
        );
      },
    );
  }

  testWidgets('reward still queued at exit keeps its reveal fallback', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('game_garage_correct', 4);
    await open(tester);
    nativeResponse = jsonEncode({
      'run_started': true,
      'finished': false,
      'answered': 7,
      'correct': 7,
      'score': 70,
      'notified_rewards': ['model:sedan'],
    });
    await launch(tester);

    expect(find.text(appL10n.gameRevealTitle), findsNothing);
    expect(find.text(appL10n.gameRevealPaintTitle), findsOneWidget);
    expect(garage.owns('sedan', 'blue'), isTrue);
    await tester.tap(find.text(appL10n.gameRevealClose));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('city voice inherits app choice without requiring premium', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_settings', jsonEncode({'voiceEnabled': true}));
    await open(tester);
    await launch(tester);
    final ride = options();
    expect(ride['voice'], isTrue);
    expect(ride['voice_available'], isTrue);
    expect(ride['sound'], isFalse);
    expect((ride['achievement'] as Map)['count'], '0 / 5');
  });

  testWidgets('voice and effects choices persist independently between rides', (
    tester,
  ) async {
    await open(tester);
    nativeResponse = jsonEncode({
      'run_started': false,
      'sound': false,
      'voice': true,
      'voice_available': true,
    });
    await launch(tester);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('godot_city_voice'), isTrue);
    expect(prefs.getBool('godot_city_sound'), isFalse);
    expect((await progress.loadAppSettings()).voiceEnabled, isFalse);
    nativeResponse = null;
    await launch(tester);
    expect(options()['voice'], isTrue);
    expect(options()['sound'], isFalse);

    nativeResponse = jsonEncode({
      'run_started': false,
      'sound': true,
      'voice': false,
      'voice_available': true,
    });
    await launch(tester);
    expect(prefs.getBool('godot_city_voice'), isFalse);
    expect(prefs.getBool('godot_city_sound'), isTrue);
    nativeResponse = null;
    await launch(tester);
    expect(options()['voice'], isFalse);
    expect(options()['sound'], isTrue);
  });

  testWidgets('unavailable languages preserve saved Russian voice preference', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('godot_city_voice', true);
    for (final language in ['en', 'kk']) {
      await open(tester, locale: Locale(language));
      nativeResponse = jsonEncode({
        'run_started': false,
        'voice': false,
        'voice_available': false,
      });
      await launch(tester);
      expect(options()['voice'], isFalse);
      expect(options()['voice_available'], isFalse);
      expect(prefs.getBool('godot_city_voice'), isTrue);
    }
    await open(tester);
    nativeResponse = null;
    await launch(tester);
    expect(options()['voice'], isTrue);
    expect(options()['voice_available'], isTrue);
  });
}
