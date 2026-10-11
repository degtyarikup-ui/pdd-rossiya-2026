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
import 'package:pdd_app/data/services/sound_effects_service.dart';
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
  static const _pendingRunKey = 'game_run_pending';
  static const _runQuestions = GameState.runQuestions;
  static Future<bool>? _available;
  static bool _running = false;

  /// Android and iOS run the game on their native screens (see ios/Runner/PddGodotGame.mm).
  static bool get _nativeScreen =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  static Future<bool> available() {
    if (kIsWeb || !_nativeScreen) {
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
    final pending = await _pendingRun();
    final selectedId = prefs?.getString(_vehicleKey) ?? GameGarageService.starter.id;
    final selectedPaint = prefs?.getString(_paintKey) ?? GameGarageService.starter.paint;
    return {
      'cars': cars,
      'selected': {'id': selectedId, 'paint': selectedPaint},
      'record': prefs?.getInt(_bestScoreKey) ?? 0,
      'tips': !(prefs?.containsKey(_tipsSeenKey) ?? false),
      // The app's own switches: sound effects and the vibration.
      'sound': SoundEffectsService.instance.isEnabled,
      'haptics': HapticFeedbackHelper.enabled,
      'can_start': unlimited || runs > 0 || pending != null,
      if (pending != null) 'resume': pending.toJson(),
      'texts': {
        'start': appL10n.gameLobbyStart,
        'new': appL10n.gameLobbyNewCar,
        'colour': appL10n.gameLobbyColour,
        'record': appL10n.gameBestScoreLabel,
        'runs': unlimited
            ? appL10n.gameRunsUnlimitedPill
            : appL10n.gameRunsPill(runs, GameRunsService.maxRuns),
        if (pending != null) 'resume': appL10n.gameLobbyContinue,
        if (pending != null)
          'resume_text': appL10n.gameLobbyProgress(pending.answered, _runQuestions),
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

  /// The result of one visit to the game: the car is kept; a run that began is
  /// charged once (a resumed one is not); the progress is booked as it goes; a run
  /// left in the middle is kept for «Продолжить заезд», a finished one shows its result.
  static Future<void> _afterGame(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> summary,
  ) async {
    final premium = ref.read(isPremiumProvider);
    final car = summary['car'];
    if (car is Map && car['id'] is String && car['paint'] is String) {
      await _saveVehicle(car['id'] as String, car['paint'] as String);
    }
    if (summary['tips_seen'] == true) {
      await _rememberTips();
    }
    if (summary['run_started'] != true) return;

    final resumed = summary['resumed'] == true;
    final finished = summary['finished'] == true;
    final pending = await _pendingRun();
    if (!resumed) {
      // The run is charged now: it began. Free players pay one run; premium is unlimited.
      if (!premium) await GameRunsService.instance.consume();
      UsageReporter.track(UsageFeature.game);
    }
    if (car is Map && car['id'] is String) {
      await _markDriven(car['id'] as String);
    }

    final correct = (summary['correct'] as num?)?.toInt() ?? 0;
    final score = (summary['score'] as num?)?.toInt() ?? 0;
    // Only what this visit added: the earlier visits of a resumed run were booked then.
    final bookedScore = resumed ? (pending?.score ?? 0) : 0;
    final bookedCorrect = resumed ? (pending?.correct ?? 0) : 0;
    final runId = resumed && pending != null
        ? pending.runId
        : GameLeaderboardService.newRunId();
    final best = await _bestScore();
    final record = score > 0 && score > best;
    await _book(
      runId: runId,
      score: score,
      delta: score - bookedScore,
      newRun: !resumed,
      record: record,
    );

    final unlocked = <GameCar>[];
    if (!premium) {
      for (var i = 0; i < correct - bookedCorrect; i++) {
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

    // Left before the last question (even before the first answer): the run waits for «Продолжить».
    if (!finished) {
      await _keepPendingRun(summary, runId: runId, score: score, correct: correct);
      return;
    }
    await _clearPendingRun();
    if (!context.mounted) return;
    await _showResult(context, ref, summary, best: best, record: record);
  }

  static Future<_PendingRun?> _pendingRun() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingRunKey);
      if (raw == null) return null;
      return _PendingRun.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _keepPendingRun(
    Map<String, dynamic> summary, {
    required String runId,
    required int score,
    required int correct,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = _PendingRun(
        runId: runId,
        answered: (summary['answered'] as num?)?.toInt() ?? 0,
        correct: correct,
        score: score,
        streak: (summary['streak'] as num?)?.toInt() ?? 0,
        violations: (summary['violations'] as num?)?.toInt() ?? 0,
        distanceM: (summary['distance_m'] as num?)?.toInt() ?? 0,
        mistakes: [for (final m in (summary['mistakes'] as List? ?? const [])) '$m'],
      );
      await prefs.setString(_pendingRunKey, jsonEncode(pending.toJson()));
    } catch (_) {
      /* Without it the run starts again next time: no money is lost, only the progress. */
    }
  }

  static Future<void> _clearPendingRun() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingRunKey);
    } catch (_) {
      /* Nothing to clear. */
    }
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

  static Future<void> _book({
    required String runId,
    required int score,
    required int delta,
    required bool newRun,
    required bool record,
  }) async {
    if (delta != 0 || newRun) {
      await GameLeaderboardService.instance.reportProgress(
        runId: runId,
        delta: delta,
        runScore: score,
        newRun: newRun,
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


/// A run left in the middle: its progress, the score and correct answers already
/// booked. «Продолжить заезд» continues it without a new charge.
class _PendingRun {
  final String runId;
  final int answered;
  final int correct;
  final int score;
  final int streak;
  final int violations;
  final int distanceM;
  final List<String> mistakes;

  const _PendingRun({
    required this.runId,
    required this.answered,
    required this.correct,
    required this.score,
    required this.streak,
    required this.violations,
    required this.distanceM,
    required this.mistakes,
  });

  factory _PendingRun.fromJson(Map<String, dynamic> json) => _PendingRun(
        runId: json['run_id'] as String? ?? GameLeaderboardService.newRunId(),
        answered: (json['answered'] as num?)?.toInt() ?? 0,
        correct: (json['correct'] as num?)?.toInt() ?? 0,
        score: (json['score'] as num?)?.toInt() ?? 0,
        streak: (json['streak'] as num?)?.toInt() ?? 0,
        violations: (json['violations'] as num?)?.toInt() ?? 0,
        distanceM: (json['distance_m'] as num?)?.toInt() ?? 0,
        mistakes: [for (final m in (json['mistakes'] as List? ?? const [])) '$m'],
      );

  /// The counters the game restores (run.gd restore) and the run's id.
  Map<String, dynamic> toJson() => {
        'run_id': runId,
        'answered': answered,
        'correct': correct,
        'score': score,
        'streak': streak,
        'violations': violations,
        'distance_m': distanceM,
        'mistakes': mistakes,
      };
}
