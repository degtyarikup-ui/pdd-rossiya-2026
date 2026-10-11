import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/game_situation.dart';
import 'package:pdd_app/data/models/question.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/game_leaderboard_service.dart';
import 'package:pdd_app/data/services/game_runs_service.dart';
import 'package:pdd_app/data/services/progress_sync_service.dart';
import 'package:pdd_app/data/services/usage_reporter.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/game/controllers/game_controller.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_fuel_widgets.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_leaderboard_sheet.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_over_dialog.dart';
import 'package:pdd_app/presentation/screens/training/training_screen.dart';
import 'package:pdd_app/presentation/widgets/premium_paywall_sheet.dart';

/// «Живой город» on Godot (game_godot/): the game runs on its own native
/// screen (Android: GodotGameActivity in the process `:game`) with its own
/// HUD, questions and driving. When the player leaves, the app books the
/// score and shows the same result sheet as the WebView game (restart, the
/// run's mistakes to work through, the rating).
///
/// Available only in a build that contains the engine (see
/// scripts/godot_android_assets.sh); elsewhere the WebView game stays.
class GodotGame {
  GodotGame._();

  static const _channel = MethodChannel('pdd/godot_game');
  static const _bestScoreKey = 'game_best_score';
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

  /// One run: pay it (free players), open the game, book the score and show
  /// the result. «Restart» in the result plays the next run the same way.
  static Future<void> play(BuildContext context, WidgetRef ref) async {
    if (_running) return;
    final unlimited = ref.read(isPremiumProvider);
    if (!unlimited) {
      await GameRunsService.instance.load();
      if (!await GameRunsService.instance.consume()) {
        if (context.mounted) _showRuns(context, ref);
        return;
      }
    }
    HapticFeedbackHelper.confirm();
    UsageReporter.track(UsageFeature.game);
    if (!context.mounted) return;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final lang = Localizations.localeOf(context).languageCode;
    _running = true;
    String? json;
    try {
      json = await _channel.invokeMethod<String>('start', {
        'args': ['--lang=$lang', if (dark) '--dark'],
      });
    } on PlatformException {
      json = null;
    } finally {
      _running = false;
    }
    if (json == null) return;
    final decoded = jsonDecode(json);
    if (decoded is! Map) return;
    final summary = decoded.cast<String, dynamic>();
    final answered = (summary['answered'] as num?)?.toInt() ?? 0;
    final score = (summary['score'] as num?)?.toInt() ?? 0;
    if (answered == 0) return;

    final best = await _bestScore();
    final record = score > 0 && score > best;
    await _book(score, record: record, best: best);
    if (!context.mounted) return;
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

  static Future<void> _book(int score, {required bool record, required int best}) async {
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
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x80000000),
      pageBuilder: (ctx, _, _) => SafeArea(
        child: Center(
          child: GameOverDialog(
            state: state,
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

  static void _showRuns(BuildContext context, WidgetRef ref) {
    showGameRunsSheet(
      context,
      maxRuns: GameState.maxRuns,
      questions: GameState.runQuestions,
      refillMinutes: GameRunsService.refillInterval.inMinutes,
      unlimited: false,
      runs: GameRunsService.instance.refresh,
      nextRefillAt: () => GameRunsService.instance.nextRefillAt,
      onBuyPremium: () => PremiumPaywallSheet.show(context),
    );
  }
}
