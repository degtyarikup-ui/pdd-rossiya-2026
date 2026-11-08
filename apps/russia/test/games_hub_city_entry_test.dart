import 'helpers/achievement_awards.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
// The real paywall is exercised with only the store boundary replaced.
// ignore: depend_on_referenced_packages
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/models/question.dart';
import 'package:pdd_app/data/sources/questions_data_source.dart';
import 'package:pdd_app/data/services/game_garage_service.dart';
import 'package:pdd_app/data/services/game_runs_service.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/game/godot_game.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_fuel_widgets.dart';
import 'package:pdd_app/presentation/screens/games/games_hub_screen.dart';
import 'package:pdd_app/presentation/widgets/premium_paywall_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const gameChannel = MethodChannel('pdd/godot_game');
  const regionChannel = MethodChannel('pdd/device_region');
  final premium = StateProvider<bool>((ref) => false);
  late ProgressDataSource progress;
  late List<String> gameCalls;

  setUpAll(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    InAppPurchase.instance;
    InAppPurchasePlatform.instance = _UnavailableStore();
    debugDefaultTargetPlatformOverride = null;
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
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    GodotGame.resetForTest();
    HapticFeedbackHelper.setEnabled(false);
    SoundEffectsService.instance.setEnabled(false);
    progress = ProgressDataSource();
    await progress.init();
    gameCalls = [];
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(gameChannel, (call) async {
      gameCalls.add(call.method);
      return call.method == 'available' ? true : null;
    });
    messenger.setMockMethodCallHandler(regionChannel, (_) async => 'US');
  });

  tearDown(() {
    HapticFeedbackHelper.setEnabled(true);
    SoundEffectsService.instance.setEnabled(true);
    debugDefaultTargetPlatformOverride = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(gameChannel, null);
    messenger.setMockMethodCallHandler(regionChannel, null);
  });

  Future<ProviderContainer> open(
    WidgetTester tester, {
    int runs = 0,
    bool pending = false,
    QuestionsDataSource? questions,
  }) async {
    GameGarageService.instance.resetForTest();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('game_runs', runs);
    await prefs.setInt(
      'game_runs_since',
      DateTime.now().millisecondsSinceEpoch,
    );
    if (pending) {
      await prefs.setString(
        'game_run_pending',
        jsonEncode({
          'run_id': 'saved-city-run',
          'answered': 3,
          'correct': 2,
          'score': 20,
        }),
      );
    }
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          noAchievementAwards,
          isAuthenticatedProvider.overrideWithValue(true),
          isPremiumProvider.overrideWith((ref) => ref.watch(premium)),
          progressDataSourceProvider.overrideWithValue(progress),
          if (questions != null)
            questionsDataSourceProvider.overrideWithValue(questions),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const GamesHubScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(GamesHubScreen)),
    );
  }

  Finder getCity() => find.byKey(const ValueKey('games-card-city'));
  Finder getRuns() => find.byKey(const ValueKey('games-runs-status'));

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  }

  Future<void> settleCityLaunch(WidgetTester tester) async {
    // Preparation and native launch each paint their loader before proceeding.
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
  }

  void expectDirectPaywall() {
    expect(
      find.byType(PremiumPaywallSheet, skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byType(GameRunsSheet, skipOffstage: false), findsNothing);
    expect(gameCalls, isEmpty);
  }

  for (final part in ['cover', 'title', 'runs']) {
    testWidgets('City $part opens paywall directly when runs are exhausted', (
      tester,
    ) async {
      await open(tester);
      final target = switch (part) {
        'title' => tester.getCenter(find.text(appL10n.gameCityTitle)),
        'runs' => tester.getCenter(getRuns()),
        _ => tester.getRect(getCity()).topRight + const Offset(-24, 24),
      };
      await tester.tapAt(target);
      await tester.pumpAndSettle();
      expectDirectPaywall();
      expect(tester.takeException(), isNull);
      await close(tester);
    });
  }

  testWidgets('Saved city run still opens paywall when no runs remain', (
    tester,
  ) async {
    await open(tester, pending: true);
    expect(await GodotGame.hasPendingRun(), isTrue);
    await tester.tapAt(tester.getCenter(find.text(appL10n.gameCityTitle)));
    await tester.pumpAndSettle();
    expectDirectPaywall();
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('Rapid city taps open one paywall and dismissal permits retry', (
    tester,
  ) async {
    await open(tester);
    final title = tester.getCenter(find.text(appL10n.gameCityTitle));
    final runs = tester.getCenter(getRuns());
    // Both taps arrive before the asynchronous runs refresh has completed.
    await tester.tapAt(runs);
    await tester.tapAt(title);
    await tester.pumpAndSettle();
    expectDirectPaywall();

    Navigator.of(tester.element(find.byType(PremiumPaywallSheet))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(PremiumPaywallSheet), findsNothing);
    await tester.tapAt(runs);
    await tester.pumpAndSettle();
    expectDirectPaywall();
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('Tapping city runs launches the game when a run is available', (
    tester,
  ) async {
    await open(tester, runs: 1);
    await tester.tapAt(tester.getCenter(getRuns()));
    await settleCityLaunch(tester);
    expect(gameCalls, ['available', 'start']);
    expect(find.byType(PremiumPaywallSheet), findsNothing);
    expect(find.byType(GameRunsSheet), findsNothing);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets(
    'returning from the native city adds canonical mistakes and retains the answer log for resume',
    (tester) async {
      final bank = (await tester.runAsync(
        () => QuestionsDataSource().loadTickets(TicketCategory.ab),
      ))!;
      final container = await open(tester, runs: 1, questions: _CityBank(bank));
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final summary = {
        'run_started': true,
        'finished': false,
        'answered': 1,
        'correct': 0,
        'score': 0,
        'mistakes': ['ticket_1_1'],
        'answer_log': [
          {'situation': 'ticket_1_1', 'correct': false, 'answeredAt': stamp},
        ],
      };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(gameChannel, (call) async {
            gameCalls.add(call.method);
            return call.method == 'available' ? true : jsonEncode(summary);
          });
      await tester.tapAt(tester.getCenter(getRuns()));
      await settleCityLaunch(tester);
      final first = bank.singleWhere(
        (q) => q.ticketNumber == 1 && q.questionNumber == 1,
      );
      expect(
        (await progress.getQuestionProgress(
          first.id,
          TicketCategory.ab,
        ))!['isCorrect'],
        false,
      );
      expect(await container.read(wrongQuestionIdsProvider.future), [first.id]);
      expect((await container.read(statsProvider.future))['wrongQuestions'], 1);
      final prefs = await SharedPreferences.getInstance();
      final pending = jsonDecode(prefs.getString('game_run_pending')!) as Map;
      expect(pending['answer_log'], summary['answer_log']);
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );

  testWidgets('Premium activated in paywall allows the next city tap', (
    tester,
  ) async {
    final container = await open(tester);
    await tester.tapAt(tester.getCenter(find.text(appL10n.gameCityTitle)));
    await tester.pumpAndSettle();
    expectDirectPaywall();

    container.read(premium.notifier).state = true;
    Navigator.of(tester.element(find.byType(PremiumPaywallSheet))).pop(true);
    await tester.pumpAndSettle();
    expect(GameRunsService.instance.runs, 0);
    await tester.tapAt(tester.getCenter(find.text(appL10n.gameCityTitle)));
    await settleCityLaunch(tester);
    expect(gameCalls, ['available', 'start']);
    expect(find.byType(PremiumPaywallSheet), findsNothing);
    expect(find.byType(GameRunsSheet), findsNothing);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('Quota exhausted during launch opens the paywall directly', (
    tester,
  ) async {
    await open(tester, runs: 1);
    final prefs = await SharedPreferences.getInstance();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(gameChannel, (call) async {
          gameCalls.add(call.method);
          if (call.method == 'available') {
            // Another launch spent the final run after the hub checked it.
            await prefs.setInt('game_runs', 0);
            return true;
          }
          return null;
        });
    await tester.tapAt(tester.getCenter(getRuns()));
    await settleCityLaunch(tester);
    expect(
      find.byType(PremiumPaywallSheet, skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byType(GameRunsSheet, skipOffstage: false), findsNothing);
    expect(gameCalls, ['available']);
    expect(tester.takeException(), isNull);
    await close(tester);
  });
  for (final id in ['parking', 'violator']) {
    group('Premium-only $id', () {
      Finder game() => find.byKey(ValueKey('games-card-$id'));
      String title() => id == 'parking'
          ? appL10n.gamesParkingTitle
          : appL10n.gamesViolatorTitle;

      Future<void> tapGame(WidgetTester tester) async {
        await tester.scrollUntilVisible(game(), 200);
        await tester.pumpAndSettle();
        await tester.tap(game());
        await tester.pumpAndSettle();
      }

      testWidgets('a free player gets the paywall that names the game', (
        tester,
      ) async {
        await open(tester, runs: 3);
        await tapGame(tester);
        expect(find.byType(PremiumPaywallSheet), findsOneWidget);
        expect(find.text(appL10n.paywallLockedGame(title())), findsOneWidget);
        expect(gameCalls, ['available']);

        // Closing the paywall stays in the hub and starts nothing.
        Navigator.of(tester.element(find.byType(PremiumPaywallSheet))).pop();
        await tester.pumpAndSettle();
        expect(find.byType(PremiumPaywallSheet), findsNothing);
        expect(gameCalls, ['available']);
        expect(tester.takeException(), isNull);
        await close(tester);
      });

      testWidgets('a purchase goes straight into the chosen game', (
        tester,
      ) async {
        final container = await open(tester, runs: 3);
        await tapGame(tester);
        expect(find.byType(PremiumPaywallSheet), findsOneWidget);
        container.read(premium.notifier).state = true;
        Navigator.of(
          tester.element(find.byType(PremiumPaywallSheet)),
        ).pop(true);
        await settleCityLaunch(tester);
        expect(find.byType(PremiumPaywallSheet), findsNothing);
        expect(gameCalls, ['available', 'start']);
        expect(find.byKey(const ValueKey('games-premium-badge')), findsNothing);
        expect(tester.takeException(), isNull);
        await close(tester);
      });

      testWidgets('an SBP browser handoff does not start the game', (
        tester,
      ) async {
        await open(tester, runs: 3);
        await tapGame(tester);
        Navigator.of(
          tester.element(find.byType(PremiumPaywallSheet)),
        ).pop(false);
        await tester.pumpAndSettle();
        expect(gameCalls, ['available']);
        expect(tester.takeException(), isNull);
        await close(tester);
      });

      testWidgets('Premium opens the game without the paywall', (tester) async {
        final container = await open(tester, runs: 3);
        container.read(premium.notifier).state = true;
        await tester.pumpAndSettle();
        await tapGame(tester);
        await settleCityLaunch(tester);
        expect(find.byType(PremiumPaywallSheet), findsNothing);
        expect(gameCalls, ['available', 'start']);
        expect(tester.takeException(), isNull);
        await close(tester);
      });

      testWidgets('a platform without the game shows no paywall', (
        tester,
      ) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(gameChannel, (call) async {
              gameCalls.add(call.method);
              return call.method == 'available' ? false : null;
            });
        await open(tester, runs: 3);
        await tapGame(tester);
        expect(find.byType(PremiumPaywallSheet), findsNothing);
        expect(find.text(appL10n.gameUnavailable), findsOneWidget);
        expect(tester.takeException(), isNull);
        await close(tester);
      });
    });
  }
}

class _UnavailableStore extends InAppPurchasePlatform {
  @override
  Future<bool> isAvailable() async => false;
}

class _CityBank extends QuestionsDataSource {
  _CityBank(this.bank);
  final List<Question> bank;
  @override
  Future<List<Question>> loadTickets(
    TicketCategory category, [
    String? lang,
  ]) async => bank;
}
