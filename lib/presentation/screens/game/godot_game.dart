import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/game_situation.dart';
import 'package:pdd_app/data/models/question.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/game_garage_service.dart';
import 'package:pdd_app/data/services/game_leaderboard_service.dart';
import 'package:pdd_app/data/services/game_runs_service.dart';
import 'package:pdd_app/data/services/progress_sync_service.dart';
import 'package:pdd_app/data/services/usage_reporter.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/game/controllers/game_controller.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_fuel_widgets.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_garage.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_leaderboard_sheet.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_over_dialog.dart';
import 'package:pdd_app/presentation/screens/training/training_screen.dart';
import 'package:pdd_app/presentation/widgets/premium_paywall_sheet.dart';

/// «Живой город» on Godot (game_godot/): the game runs on its own native
/// screen (Android: GodotGameActivity in the process `:game`). The garage
/// (lobby) comes first; the run is charged when it actually starts; when the
/// player leaves, the app saves the car, books the score, grants the cars
/// earned by the correct answers and shows the result (restart, the run's
/// mistakes, the rating) — the same screens as the WebView game.
///
/// Available only in a build that contains the engine (see
/// scripts/godot_android_assets.sh); elsewhere the WebView game stays.
class GodotGame {
  GodotGame._();

  static const _channel = MethodChannel('pdd/godot_game');
  static const _bestScoreKey = 'game_best_score';
  static const _vehicleKey = 'game_vehicle';
  static const _paintKey = 'game_vehicle_paint';
  static const _seenModelsKey = 'game_seen_models';
  // The same keys as the WebView game (game_screen.dart): the tips and the first-drive gas hint.
  static const _tipsSeenKey = 'game_tips_seen';
  static const _firstRunSeenKey = 'game_seen';
  static Future<bool>? _available;
  static bool _running = false;

  static Future<bool> available() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(false);
    }
    return _available ??= _channel
        .invokeMethod<bool>('available')
        .then((v) => v ?? false)
        .catchError((_) => false);
  }

  /// The garage, a run and the result. «Restart» in the result opens the
  /// garage again, as the WebView game does.
  static Future<void> play(BuildContext context, WidgetRef ref) async {
    if (_running) return;
    HapticFeedbackHelper.tap();
    final lang = Localizations.localeOf(context).languageCode;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final garage = await _garageJson(ref, lang: lang);
    _running = true;
    String? json;
    try {
      json = await _channel.invokeMethod<String>('start', {
        'args': [
          '--lang=$lang',
          if (dark) '--dark',
          '--garage=${jsonEncode(garage)}',
        ],
      });
    } on PlatformException {
      json = null;
    } finally {
      _running = false;
    }
    if (json == null) return;
    final decoded = jsonDecode(json);
    if (decoded is! Map || !context.mounted) return;
    await _afterGame(context, ref, decoded.cast<String, dynamic>());
  }

  /// Everything the lobby shows, in the app's own words and cars.
  static Future<Map<String, dynamic>> _garageJson(
    WidgetRef ref, {
    required String lang,
  }) async {
    final premium = ref.read(isPremiumProvider);
    await GameGarageService.instance.load();
    final runs = GameRunsService.instance.refresh();
    final unlimited = premium;
    final owned = GameGarageService.instance.cars;
    final seen = await _seenModels();
    final prefs = await _prefs();
    final ids = premium
        ? gameVehicleIds
        : [
            for (final id in gameVehicleIds)
              if (owned.any((c) => c.id == id)) id,
          ];
    final cars = [
      for (final id in ids)
        {
          'id': id,
          'name': gameCarName(id),
          // «НОВАЯ» until the model has been driven once (seen == null: no badge).
          'new': seen != null && !seen.contains(id),
          'paints': [
            for (final paint in premium
                ? gamePaintColors.keys
                : [
                    for (final c in owned)
                      if (c.id == id) c.paint,
                  ])
              {
                'paint': paint,
                'name': gamePaintName(paint),
                'hex': _hex(gamePaintColors[paint]!),
              },
          ],
        },
    ];
    final selectedId = prefs?.getString(_vehicleKey) ?? GameGarageService.starter.id;
    final selectedPaint = prefs?.getString(_paintKey) ?? GameGarageService.starter.paint;
    return {
      'cars': cars,
      'selected': {'id': selectedId, 'paint': selectedPaint},
      'record': prefs?.getInt(_bestScoreKey) ?? 0,
      'tips': !(prefs?.containsKey(_tipsSeenKey) ?? false),
      'can_start': unlimited || runs > 0,
      'texts': {
        'start': appL10n.gameLobbyStart,
        'new': appL10n.gameLobbyNewCar,
        'colour': appL10n.gameLobbyColour,
        'record': appL10n.gameBestScoreLabel,
        'runs': unlimited
            ? appL10n.gameRunsUnlimitedPill
            : appL10n.gameRunsPill(runs, GameRunsService.maxRuns),
        'no_runs': appL10n.gameRunsNextIn(
          gameFuelCountdown(GameRunsService.instance.nextRefillAt),
        ),
      },
      'lang': lang,
    };
  }

  static String _hex(Color c) {
    String channel(double v) => (v * 255).round().toRadixString(16).padLeft(2, '0');
    return '#${channel(c.r)}${channel(c.g)}${channel(c.b)}'.toUpperCase();
  }

  static Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  /// Models already driven; null: never recorded, so no «НОВАЯ» badge.
  static Future<Set<String>?> _seenModels() async {
    final list = (await _prefs())?.getStringList(_seenModelsKey);
    return list?.toSet();
  }

  static Future<void> _afterGame(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> summary,
  ) async {
    final premium = ref.read(isPremiumProvider);
    final started = summary['run_started'] == true;
    final car = summary['car'];
    if (car is Map && car['id'] is String && car['paint'] is String) {
      await _saveVehicle(car['id'] as String, car['paint'] as String);
    }
    if (summary['tips_seen'] == true) {
      await _rememberTips();
    }
    if (!started) return;

    // The run is charged now: it began. Free players pay one run; premium is unlimited.
    if (!ref.read(isPremiumProvider)) {
      await GameRunsService.instance.consume();
    }
    UsageReporter.track(UsageFeature.game);
    if (car is Map && car['id'] is String) {
      await _markDriven(car['id'] as String);
    }

    final answered = (summary['answered'] as num?)?.toInt() ?? 0;
    final correct = (summary['correct'] as num?)?.toInt() ?? 0;
    final score = (summary['score'] as num?)?.toInt() ?? 0;
    final best = await _bestScore();
    final record = score > 0 && score > best;
    await _book(score, record: record);

    final unlocked = <GameCar>[];
    if (!premium) {
      for (var i = 0; i < correct; i++) {
        final car = await GameGarageService.instance.recordCorrect();
        if (car != null) unlocked.add(car);
      }
      if (unlocked.isNotEmpty) {
        unawaited(ProgressSyncService.instance.syncWithServer());
      }
    }
    if (!context.mounted) return;
    for (final car in unlocked) {
      await _showReveal(context, car);
      if (!context.mounted) return;
    }
    if (answered == 0 || !context.mounted) return;
    await _showResult(context, ref, summary, best: best, record: record);
  }

  static Future<int> _bestScore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_bestScoreKey) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> _saveVehicle(String id, String paint) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_vehicleKey, id);
      await prefs.setString(_paintKey, paint);
    } catch (_) {
      /* The car is kept for the next garage visit; a failed save is not a game error. */
    }
  }

  static Future<void> _rememberTips() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_tipsSeenKey, true);
      await prefs.setBool(_firstRunSeenKey, true);
    } catch (_) {
      /* The tips come back next time: harmless. */
    }
  }

  static Future<void> _markDriven(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_seenModelsKey);
      if (list != null && !list.contains(id)) {
        await prefs.setStringList(_seenModelsKey, [...list, id]);
      }
    } catch (_) {
      /* Only the «НОВАЯ» badge depends on it. */
    }
  }

  static Future<void> _book(int score, {required bool record}) async {
    if (score > 0) {
      await GameLeaderboardService.instance.reportProgress(
        runId: GameLeaderboardService.newRunId(),
        delta: score,
        runScore: score,
        newRun: true,
      );
    }
    if (record) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_bestScoreKey, score);
      } catch (_) {
        /* The rating has the score; the local best is a convenience. */
      }
    }
    unawaited(ProgressSyncService.instance.syncWithServer());
  }

  /// «Новая машина!» — the car earned by the run's correct answers. Choosing it
  /// makes it the car of the next garage visit.
  static Future<void> _showReveal(BuildContext context, GameCar car) async {
    final colors = AppColors.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.cardBackground,
        surfaceTintColor: Colors.transparent,
        title: Text(appL10n.gameRevealTitle),
        content: Text('${gameCarName(car.id)} · ${gamePaintName(car.paint)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(appL10n.gameRevealClose),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              unawaited(_saveVehicle(car.id, car.paint));
            },
            child: Text(appL10n.gameRevealChoose),
          ),
        ],
      ),
    );
  }

  static Future<void> _showResult(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> summary, {
    required int best,
    required bool record,
  }) async {
    final mistakes = <GameSituation>[
      for (final id in (summary['mistakes'] as List? ?? const []))
        _situationOf('$id'),
    ];
    final state = GameState(
      score: (summary['score'] as num?)?.toInt() ?? 0,
      totalAnswered: (summary['answered'] as num?)?.toInt() ?? 0,
      totalCorrect: (summary['correct'] as num?)?.toInt() ?? 0,
      totalMistakes: mistakes.length,
      violationCount: (summary['violations'] as num?)?.toInt() ?? 0,
      distanceM: (summary['distance_m'] as num?)?.toInt() ?? 0,
      mistakes: mistakes,
      phase: GamePhase.gameOver,
    );
    final prefs = await _prefs();
    final car = prefs?.getString(_vehicleKey) ?? GameGarageService.starter.id;
    final paint = prefs?.getString(_paintKey) ?? GameGarageService.starter.paint;
    if (!context.mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x80000000),
      pageBuilder: (ctx, _, _) => SafeArea(
        child: Center(
          child: GameOverDialog(
            state: state,
            vehicleId: car,
            vehiclePaint: paint,
            thumbnailCache: const {},
            onRestart: () {
              Navigator.of(ctx).pop();
              if (context.mounted) unawaited(play(context, ref));
            },
            onExit: () => Navigator.of(ctx).pop(),
            onLeaderboard: () => GameLeaderboardSheet.show(context),
            onReviewMistakes: (list) => reviewMistakes(context, ref, list),
            fuelRefillAt: GameRunsService.instance.firstUnitAt,
            onBuyPremium: () => PremiumPaywallSheet.show(context),
            bestScore: record ? null : best,
            isNewRecord: record,
          ),
        ),
      ),
    );
  }

  /// The Godot situation id («ticket_10_13») as the app's ticket reference: the
  /// review finds the question by its ticket and number.
  static GameSituation _situationOf(String sceneId) {
    final ticket = sceneId.replaceFirst('ticket_', '').replaceAll('_', '·');
    return GameSituation(
      id: sceneId,
      ticket: ticket,
      title: '',
      explanation: '',
      pddRule: '',
      options: const [],
      correctAnswerIndex: 0,
      legend: const [],
      type: '',
    );
  }

  static List<Question>? _abQuestions;

  /// The run's mistakes as ticket questions to work through (the same screen
  /// as the WebView game's «Разобрать ошибки»).
  static Future<void> reviewMistakes(
    BuildContext context,
    WidgetRef ref,
    List<GameSituation> mistakes,
  ) async {
    HapticFeedbackHelper.tap();
    final questions = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final m in mistakes) {
      if (m.country != null && m.country != CountryConfig.current.code) {
        continue;
      }
      try {
        final q = await _questionFor(ref, m);
        if (q != null && seen.add(q.id)) questions.add(q.toMap());
      } catch (e) {
        debugPrint('Game mistake not found: $e');
      }
    }
    if (!context.mounted || questions.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TrainingScreen(
          questions: questions,
          title: questions.length == 1
              ? appL10n.mistakeReview
              : appL10n.mistakesTitle,
        ),
      ),
    );
  }

  static Future<Question?> _questionFor(WidgetRef ref, GameSituation situation) async {
    _abQuestions ??= await ref
        .read(questionsDataSourceProvider)
        .loadTickets(TicketCategory.ab);
    final questions = _abQuestions!;
    final id = situation.sourceQuestionId;
    if (id != null && id.isNotEmpty) {
      for (final q in questions) {
        if (q.id == id) return q;
      }
    }
    final m = RegExp(r'(\d+)\D+(\d+)').firstMatch(situation.ticket);
    if (m == null) return null;
    final ticket = int.parse(m.group(1)!), number = int.parse(m.group(2)!);
    final inTicket = questions.where((q) => q.ticketNumber == ticket).toList();
    if (number < 1 || number > inTicket.length) return null;
    return inTicket[number - 1];
  }
}
