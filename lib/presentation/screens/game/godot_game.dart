import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/config/game_economy.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/crossroads_priority_progress.dart';
import 'package:pdd_app/data/models/game_situation.dart';
import 'package:pdd_app/data/models/question.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/game_garage_service.dart';
import 'package:pdd_app/data/services/game_leaderboard_service.dart';
import 'package:pdd_app/data/services/game_question_history_service.dart';
import 'package:pdd_app/data/services/game_runs_service.dart';
import 'package:pdd_app/data/services/progress_sync_service.dart';
import 'package:pdd_app/data/services/review_prompt_service.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/data/services/usage_reporter.dart';
import 'package:pdd_app/data/services/question_report_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/game/controllers/game_controller.dart';
import 'package:pdd_app/presentation/screens/game/godot_web_screen.dart';
import 'package:pdd_app/presentation/screens/game/platform/godot_web_frame.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_fuel_widgets.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_garage.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_leaderboard_sheet.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_over_dialog.dart';
import 'package:pdd_app/presentation/screens/training/training_screen.dart';
import 'package:pdd_app/presentation/widgets/premium_paywall_sheet.dart';
import 'package:pdd_app/presentation/widgets/app_loading_indicator.dart';

/// «Живой город» on Godot (game_godot/): the game runs on its own native
/// screen (Android: GodotGameActivity in the process `:game`). The ride
/// starts immediately and is charged once; when the
/// player leaves, the app saves the car, books the score, grants the cars
/// earned by the correct answers and shows the result (restart, the run's
/// mistakes, the rating) — the same screens as the WebView game.
///
/// Available only in a build that contains the engine (see
/// scripts/godot_android_assets.sh); elsewhere the app reports that the game is unavailable.
class GodotGame {
  GodotGame._();

  static const _channel = MethodChannel('pdd/godot_game');
  static const _bestScoreKey = 'game_best_score';
  static const _vehicleKey = 'game_vehicle';
  static const _paintKey = 'game_vehicle_paint';
  static const _seenModelsKey = 'game_seen_models';
  // The tips and the first-drive gas hint.
  static const _tipsSeenKey = 'game_tips_seen';
  static const _firstRunSeenKey = 'game_seen';
  static const _pendingRunKey = 'game_run_pending';
  // Per-game sound preference, preserved after leaving a ride.
  static const _citySoundKey = 'godot_city_sound';
  static const _cityVoiceKey = 'godot_city_voice';
  static const _cityPerfKey = 'godot_city_perf';
  static const _runQuestions = GameState.runQuestions;
  static Future<bool>? _available;
  static Future<bool>? _webAvailable;
  static int _nextRunToken = 0;
  static int? _activeRunToken;

  @visibleForTesting
  static void resetForTest() {
    _available = null;
    _webAvailable = null;
    _activeRunToken = null;
    // This wrapper itself is test-only, and resets all city-bridge state.
    // ignore: invalid_use_of_visible_for_testing_member
    GameQuestionHistoryService.instance.resetForTest();
  }

  /// Android and iOS run the game on their native screens (see ios/Runner/PddGodotGame.mm).
  static bool get _nativeScreen =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  static Future<bool> available() {
    if (kIsWeb) {
      return _webAvailable ??= GodotWebFrame.available();
    }
    if (!_nativeScreen) {
      return Future.value(false);
    }
    return _available ??= _channel
        .invokeMethod<bool>('available')
        .timeout(const Duration(seconds: 2), onTimeout: () => false)
        .then((v) => v ?? false)
        .catchError((_) => false);
  }

  /// Starts or resumes a ride immediately; the owned collection is available in pause.
  static Future<void> play(BuildContext context, WidgetRef ref) =>
      _withRun(context, (token) => _play(context, ref, token));

  static Future<void> _withRun(
    BuildContext context,
    Future<void> Function(int token) work,
  ) async {
    if (!context.mounted || _activeRunToken != null) return;
    final token = ++_nextRunToken;
    _activeRunToken = token;
    try {
      await work(token);
    } finally {
      _releaseRun(token);
    }
  }

  static void _releaseRun(int token) {
    // An interactive result can start a fresh run before the preceding dialog
    // future completes. Its older finally must never release the new run.
    if (_activeRunToken == token) _activeRunToken = null;
  }

  static Future<void> _play(
    BuildContext context,
    WidgetRef ref,
    int token,
  ) async {
    HapticFeedbackHelper.tap();
    final lang = Localizations.localeOf(context).languageCode;
    final options = await _prepare(
      context,
      () => _rideOptions(ref, lang: lang),
    );
    if (!context.mounted || options == null) return;
    if (options['can_start'] != true) {
      _releaseRun(token);
      await PremiumPaywallSheet.show(context);
      return;
    }
    final safe = _safeArea(context);
    String? json;
    try {
      json = await _start(context, [
        '--lang=$lang',
        '--text-scale=${MediaQuery.textScalerOf(context).scale(14) / 14}',
        Theme.of(context).brightness == Brightness.dark ? '--dark' : '--light',
        ...safe,
        '--ride-options=${jsonEncode(options)}',
        if (const bool.fromEnvironment('GAME_DEBUG') &&
            options['debug_perf'] == true)
          '--perf',
        if (const bool.fromEnvironment('GAME_DEBUG')) '--debug-menu',
      ]);
    } on PlatformException {
      json = null;
    }
    if (json == null) return;
    final decoded = jsonDecode(json);
    if (decoded is! Map) return;
    // History is persistent game data, even if its launching route was closed.
    // It does not access WidgetRef, so it can complete without a mounted UI.
    final historyLoading = context.mounted
        ? AppLoadingOverlay.show(context, label: appL10n.gameReturning)
        : null;
    try {
      if (historyLoading != null) await WidgetsBinding.instance.endOfFrame;
      await GameQuestionHistoryService.instance.recordSnapshot(
        decoded['question_history'],
      );
    } finally {
      historyLoading?.close();
    }
    if (!context.mounted) return;
    final summary = decoded.cast<String, dynamic>();
    final previous = summary['city_runs'];
    if (previous is List) {
      for (final run in previous.whereType<Map>()) {
        if (!context.mounted) return;
        await _afterGame(context, ref, run.cast<String, dynamic>(), token);
      }
    }
    if (!context.mounted) return;
    await _afterGame(context, ref, summary, token);
    if (!context.mounted) return;
    if (summary['result_action'] == 'ranking') {
      await GameLeaderboardSheet.show(context);
    } else if (summary['result_action'] == 'mistakes') {
      await reviewMistakes(context, ref, [
        for (final id in summary['mistakes'] as List? ?? const [])
          _situationOf('$id'),
      ]);
    }
  }

  /// Plays the 3D Regulator mini-game on Godot.
  static Future<void> playRegulator(BuildContext context, WidgetRef ref) =>
      _withRun(context, (_) => _playRegulator(context, ref));

  static Future<void> _playRegulator(
    BuildContext context,
    WidgetRef ref,
  ) async {
    HapticFeedbackHelper.tap();
    final lang = Localizations.localeOf(context).languageCode;
    final prefs = await _prepare(context, _prefs);
    if (!context.mounted) return;
    final vehicle = prefs?.getString(_vehicleKey) ?? 'sedan';
    final paint = GameGarageService.normalizePaint(
      prefs?.getString(_paintKey) ?? GameGarageService.starter.paint,
    );
    final paintHex = _hex(gamePaintColors[paint]!);
    if (!context.mounted) return;
    final safe = _safeArea(context);
    String? json;
    try {
      json = await _start(context, [
        '--regulator',
        '--text-scale=${MediaQuery.textScalerOf(context).scale(14) / 14}',
        '--best-score=${ref.read(trafficControllerProgressProvider).bestScore}',
        '--session-id=${GameLeaderboardService.newRunId()}',
        '--economy=${jsonEncode({'seconds': GameEconomy.miniGameSeconds, 'lives': GameEconomy.miniGameLives, 'maxScore': GameEconomy.maxRunScore, 'base': GameEconomy.regulator(1), 'step': GameEconomy.regulator(2) - GameEconomy.regulator(1), 'bonusCap': 4})}',
        if (!HapticFeedbackHelper.enabled) '--no-haptics',
        '--lang=$lang',
        Theme.of(context).brightness == Brightness.dark ? '--dark' : '--light',
        ...safe,
        '--vehicle=$vehicle',
        '--paint=$paintHex',
        if (!SoundEffectsService.instance.isEnabled) '--mute',
      ]);
    } on PlatformException {
      json = null;
    }
    if (json == null) return;
    final decoded = jsonDecode(json);
    if (decoded is! Map || !context.mounted) return;
    final map = decoded.cast<String, dynamic>();
    // A single native screen can contain several restarted rounds. Book each
    // round separately, including an unfinished round left with system Back.
    final loading = AppLoadingOverlay.show(
      context,
      label: appL10n.gameReturning,
    );
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!context.mounted) return;
      final progress = ref.read(trafficControllerProgressProvider.notifier);
      final runs = map['runs'] is List ? map['runs'] as List : [map];
      final seen = <String>{};
      final rankingSubmissions = <Future<int?>>[];
      var changed = false;
      for (final run in runs.whereType<Map>()) {
        final id = run['id'] as String? ?? GameLeaderboardService.newRunId();
        if (!seen.add(id)) continue;
        final solved = ((run['solved'] as num?)?.toInt() ?? 0).clamp(0, 10000);
        final wrong = ((run['wrong'] as num?)?.toInt() ?? 0).clamp(0, 10000);
        if (solved + wrong == 0) continue;
        UsageReporter.track(UsageFeature.trafficController);
        final score = GameEconomy.rankedScore(
          (run['score'] as num?)?.toInt() ?? 0,
          correct: solved,
          wrong: wrong,
        );
        final combo = ((run['combo'] as num?)?.toInt() ?? 0).clamp(0, solved);
        final submission = GameLeaderboardService.instance.submitRun(
          score,
          runId: id,
        );
        if (map['result_action'] == 'ranking') {
          rankingSubmissions.add(submission);
        } else {
          unawaited(submission);
        }
        await progress.recordGameResult(
          score: score,
          combo: combo,
          solved: solved,
        );
        changed = true;
      }
      if (rankingSubmissions.isNotEmpty) await Future.wait(rankingSubmissions);
      if (changed) unawaited(ProgressSyncService.instance.syncWithServer());
    } finally {
      loading.close();
    }
    if (context.mounted && map['result_action'] == 'ranking') {
      await GameLeaderboardSheet.show(context);
    }
  }

  /// Plays the 3D Crossroads Priority mini-game on Godot.
  static Future<void> playCrossroads(BuildContext context, WidgetRef ref) =>
      _withRun(
        context,
        (_) => _playCrossroads(
          context,
          ref,
          flag: '--crossroads',
          progressProvider: crossroadsPriorityProgressProvider,
          feature: UsageFeature.crossroads,
          economy: {
            'seconds': GameEconomy.miniGameSeconds,
            'lives': GameEconomy.miniGameLives,
            'maxScore': GameEconomy.maxRunScore,
            'base': GameEconomy.crossroads(1),
            'step': GameEconomy.crossroads(2) - GameEconomy.crossroads(1),
            'bonusCap': 5,
          },
        ),
      );

  /// Plays the 3D «Парковка» mini-game on Godot (same flow as the crossroads).
  static Future<void> playParking(BuildContext context, WidgetRef ref) =>
      _withRun(
        context,
        (_) => _playCrossroads(
          context,
          ref,
          flag: '--parking',
          progressProvider: parkingProgressProvider,
          feature: UsageFeature.parking,
          economy: {
            'lives': GameEconomy.miniGameLives,
            'maxScore': GameEconomy.maxRunScore,
          },
        ),
      );

  static Future<void> _playCrossroads(
    BuildContext context,
    WidgetRef ref, {
    required String flag,
    required StateNotifierProvider<
      CrossroadsPriorityProgressController,
      CrossroadsPriorityProgress
    >
    progressProvider,
    required UsageFeature feature,
    required Map<String, Object> economy,
  }) async {
    HapticFeedbackHelper.tap();
    final lang = Localizations.localeOf(context).languageCode;
    final prefs = await _prepare(context, _prefs);
    if (!context.mounted) return;
    final vehicle = prefs?.getString(_vehicleKey) ?? 'sedan';
    final paint = GameGarageService.normalizePaint(
      prefs?.getString(_paintKey) ?? GameGarageService.starter.paint,
    );
    final paintHex = _hex(gamePaintColors[paint]!);
    if (!context.mounted) return;
    final safe = _safeArea(context);
    String? json;
    try {
      json = await _start(context, [
        flag,
        '--text-scale=${MediaQuery.textScalerOf(context).scale(14) / 14}',
        '--best-score=${ref.read(progressProvider).bestScore}',
        '--session-id=${GameLeaderboardService.newRunId()}',
        '--economy=${jsonEncode(economy)}',
        if (!HapticFeedbackHelper.enabled) '--no-haptics',
        '--lang=$lang',
        Theme.of(context).brightness == Brightness.dark ? '--dark' : '--light',
        ...safe,
        '--vehicle=$vehicle',
        '--paint=$paintHex',
        if (!SoundEffectsService.instance.isEnabled) '--mute',
      ]);
    } on PlatformException {
      json = null;
    }
    if (json == null) return;
    final decoded = jsonDecode(json);
    if (decoded is! Map || !context.mounted) return;
    final map = decoded.cast<String, dynamic>();
    final loading = AppLoadingOverlay.show(
      context,
      label: appL10n.gameReturning,
    );
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!context.mounted) return;
      final progress = ref.read(progressProvider.notifier);
      final runs = map['runs'] is List ? map['runs'] as List : [map];
      final seen = <String>{};
      final rankingSubmissions = <Future<int?>>[];
      var changed = false;
      for (final run in runs.whereType<Map>()) {
        final id = run['id'] as String? ?? GameLeaderboardService.newRunId();
        if (!seen.add(id)) continue;
        final solved = ((run['solved'] as num?)?.toInt() ?? 0).clamp(0, 10000);
        final wrong = ((run['wrong'] as num?)?.toInt() ?? 0).clamp(0, 10000);
        if (solved + wrong == 0) continue;
        UsageReporter.track(feature);
        final score = GameEconomy.rankedScore(
          (run['score'] as num?)?.toInt() ?? 0,
          correct: solved,
          wrong: wrong,
        );
        final combo = ((run['combo'] as num?)?.toInt() ?? 0).clamp(0, solved);
        final submission = GameLeaderboardService.instance.submitRun(
          score,
          runId: id,
        );
        if (map['result_action'] == 'ranking') {
          rankingSubmissions.add(submission);
        } else {
          unawaited(submission);
        }
        await progress.recordGameResult(
          score: score,
          combo: combo,
          solved: solved,
        );
        changed = true;
      }
      if (rankingSubmissions.isNotEmpty) await Future.wait(rankingSubmissions);
      if (changed) unawaited(ProgressSyncService.instance.syncWithServer());
    } finally {
      loading.close();
    }
    if (context.mounted && map['result_action'] == 'ranking') {
      await GameLeaderboardSheet.show(context);
    }
  }

  /// Plays the 3D Violator mini-game on Godot.
  static Future<void> playViolator(BuildContext context, WidgetRef ref) =>
      _withRun(context, (_) => _playViolator(context, ref));

  static Future<void> _playViolator(
    BuildContext context,
    WidgetRef ref,
  ) async {
    HapticFeedbackHelper.tap();
    final lang = Localizations.localeOf(context).languageCode;
    final prefs = await _prepare(context, _prefs);
    if (!context.mounted) return;
    final vehicle = prefs?.getString(_vehicleKey) ?? 'sedan';
    final paint = GameGarageService.normalizePaint(
      prefs?.getString(_paintKey) ?? GameGarageService.starter.paint,
    );
    final paintHex = _hex(gamePaintColors[paint]!);
    if (!context.mounted) return;
    final safe = _safeArea(context);
    String? json;
    try {
      json = await _start(context, [
        '--violator',
        '--text-scale=${MediaQuery.textScalerOf(context).scale(14) / 14}',
        '--best-score=${ref.read(violatorProgressProvider).bestScore}',
        '--session-id=${GameLeaderboardService.newRunId()}',
        '--economy=${jsonEncode({'seconds': GameEconomy.violatorSeconds, 'lives': GameEconomy.miniGameLives, 'maxScore': GameEconomy.maxRunScore, 'base': 50, 'step': 5, 'bonusCap': 5})}',
        if (!HapticFeedbackHelper.enabled) '--no-haptics',
        '--lang=$lang',
        Theme.of(context).brightness == Brightness.dark ? '--dark' : '--light',
        ...safe,
        '--vehicle=$vehicle',
        '--paint=$paintHex',
        if (!SoundEffectsService.instance.isEnabled) '--mute',
      ]);
    } on PlatformException {
      json = null;
    }
    if (json == null) return;
    final decoded = jsonDecode(json);
    if (decoded is! Map || !context.mounted) return;
    final map = decoded.cast<String, dynamic>();
    final loading = AppLoadingOverlay.show(
      context,
      label: appL10n.gameReturning,
    );
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!context.mounted) return;
      final progress = ref.read(violatorProgressProvider.notifier);
      final runs = map['runs'] is List ? map['runs'] as List : [map];
      final seen = <String>{};
      final rankingSubmissions = <Future<int?>>[];
      var changed = false;
      for (final run in runs.whereType<Map>()) {
        final id = run['id'] as String? ?? GameLeaderboardService.newRunId();
        if (!seen.add(id)) continue;
        final solved = ((run['solved'] as num?)?.toInt() ?? 0).clamp(0, 10000);
        final wrong = ((run['wrong'] as num?)?.toInt() ?? 0).clamp(0, 10000);
        if (solved + wrong == 0) continue;
        final score = GameEconomy.rankedScore(
          (run['score'] as num?)?.toInt() ?? 0,
          correct: solved,
          wrong: wrong,
        );
        final combo = ((run['combo'] as num?)?.toInt() ?? 0).clamp(0, solved);
        final submission = GameLeaderboardService.instance.submitRun(
          score,
          runId: id,
        );
        if (map['result_action'] == 'ranking') {
          rankingSubmissions.add(submission);
        } else {
          unawaited(submission);
        }
        await progress.recordGameResult(
          score: score,
          combo: combo,
          solved: solved,
        );
        changed = true;
      }
      if (rankingSubmissions.isNotEmpty) await Future.wait(rankingSubmissions);
      if (changed) unawaited(ProgressSyncService.instance.syncWithServer());
    } finally {
      loading.close();
    }
    if (context.mounted && map['result_action'] == 'ranking') {
      await GameLeaderboardSheet.show(context);
    }
  }

  /// Opens the game and waits for its summary (JSON), null if it did not end
  /// with one. Android and iOS: the native screen; web: the game's route.
  /// The layout the app measures, in dp: the status and navigation bars (the engine does not report the
  /// status bar on Android, so the game would draw its top bar under it) and the screen width, which
  /// sets the game's dp scale (Ui.dp) so its sizes are the app's sizes.
  static List<String> _safeArea(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final width = MediaQuery.sizeOf(context).width;
    return [
      '--safe-top=${padding.top.toStringAsFixed(1)}',
      '--safe-bottom=${padding.bottom.toStringAsFixed(1)}',
      '--screen-dp=${width.toStringAsFixed(1)}',
    ];
  }

  static Future<T?> _prepare<T>(
    BuildContext context,
    Future<T> Function() work, {
    String? label,
  }) async {
    if (!context.mounted) return null;
    final loading = AppLoadingOverlay.show(
      context,
      label: label ?? appL10n.gameLoading,
    );
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!context.mounted) return null;
      return await work();
    } finally {
      loading.close();
    }
  }

  static Future<String?> _start(BuildContext context, List<String> args) async {
    final overlay = AppLoadingOverlay.show(context, label: appL10n.gameLoading);
    args = [
      ...args,
      '--loading-label=${appL10n.gameLoading}',
      '--returning-label=${appL10n.gameReturning}',
      if (MediaQuery.disableAnimationsOf(context)) '--reduce-motion',
      if (const bool.fromEnvironment('GAME_DEBUG')) '--loader-profile',
    ];
    if (!kIsWeb) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'reportQuestion' && call.arguments is String) {
          try {
            final report = jsonDecode(call.arguments as String);
            if (report is Map<String, dynamic>) {
              return await QuestionReportService.sendGameReport(report);
            }
          } catch (_) {}
          return false;
        }
        if (call.method != 'loading' || call.arguments is! Map) return null;
        final data = call.arguments as Map;
        overlay.setVisible(
          data['visible'] == true,
          label: data['phase'] == 'returning'
              ? appL10n.gameReturning
              : appL10n.gameLoading,
        );
        // UIKit can reveal/hide its window only after this Flutter frame.
        await WidgetsBinding.instance.endOfFrame;
        return null;
      });
    }
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!context.mounted) return null;
      final String? result;
      if (kIsWeb) {
        // The web route owns its own loading surface above the iframe.
        overlay.close();
        result = await Navigator.of(
          context,
        ).push<String>(GodotWebScreen.route(args: args));
      } else {
        result = await _channel.invokeMethod<String>('start', {'args': args});
      }
      if (context.mounted) {
        overlay.setVisible(true, label: appL10n.gameReturning);
        await WidgetsBinding.instance.endOfFrame;
      }
      return result;
    } finally {
      if (!kIsWeb) {
        _channel.setMethodCallHandler(null);
      }
      overlay.close();
    }
  }

  /// Owned cars/paints and settings for immediate start and the pause menu.
  static Future<Map<String, dynamic>> _rideOptions(
    WidgetRef ref, {
    required String lang,
  }) async {
    final premium = ref.read(isPremiumProvider);
    final settings = await ref
        .read(progressDataSourceProvider)
        .loadAppSettings();
    final garage = GameGarageService.instance;
    await garage.load();
    await GameRunsService.instance.load();
    final runs = GameRunsService.instance.refresh();
    final unlimited = premium;
    final seen = await _seenModels();
    final prefs = await _prefs();
    final ids = premium ? gameVehicleIds : garage.ownedModels;
    final paints = premium ? GameGarageService.paints : garage.ownedPaints;
    final cars = [
      for (final id in ids)
        {
          'id': id,
          'name': gameCarName(id),
          // «НОВАЯ» until the model has been driven once (seen == null: no badge).
          'new': seen != null && !seen.contains(id),
          'paints': [
            for (final paint in paints)
              {
                'paint': paint,
                'name': gamePaintName(paint),
                'hex': _hex(gamePaintColors[paint]!),
              },
          ],
        },
    ];
    final pending = await _pendingRun();
    final savedId = prefs?.getString(_vehicleKey);
    final selectedId = ids.contains(savedId)
        ? savedId!
        : GameGarageService.starter.id;
    final savedPaint = prefs?.getString(_paintKey);
    final normalizedPaint = GameGarageService.normalizePaint(
      savedPaint ?? 'red',
    );
    final selectedPaint = paints.contains(normalizedPaint)
        ? normalizedPaint
        : GameGarageService.starter.paint;
    if (savedId != selectedId || savedPaint != selectedPaint) {
      await _saveVehicle(selectedId, selectedPaint);
    }
    final nextReward = garage.nextReward;
    final target =
        nextReward?.threshold ?? GameGarageService.rewards.last.threshold;
    final voiceAvailable = lang == 'ru';
    final voice = prefs?.getBool(_cityVoiceKey) ?? settings.voiceEnabled;
    return {
      'cars': cars,
      'selected': {'id': selectedId, 'paint': selectedPaint},
      'garage_correct': garage.correctTotal,
      'garage_premium': premium,
      'achievement': {
        'title': appL10n.gameAchievementsTitle,
        'hint': appL10n.gameAchievementsHint,
        'count': appL10n.gameAchievementCount(garage.correctTotal, target),
        'progress': appL10n.gameAchievementProgress(
          garage.correctTotal,
          target,
        ),
        'next': nextReward == null
            ? appL10n.gameAchievementsComplete
            : gameRewardName(nextReward),
        'complete': nextReward == null,
        'fraction': gameAchievementFraction(garage),
      },
      'reward_list': [
        for (final reward in GameGarageService.rewards)
          {
            'title': gameRewardName(reward),
            'progress': appL10n.gameAchievementProgress(
              garage.correctTotal.clamp(0, reward.threshold),
              reward.threshold,
            ),
            'unlocked': garage.hasReward(reward),
            'threshold': reward.threshold,
            if (reward.model != null) 'model': reward.model,
            if (reward.paint != null) 'paint': reward.paint,
          },
      ],
      'reward_models': [
        for (final id in GameGarageService.models)
          {'id': id, 'name': gameCarName(id), 'new': true},
      ],
      'reward_paints': [
        for (final paint in GameGarageService.paints)
          {
            'paint': paint,
            'name': gamePaintName(paint),
            'hex': _hex(gamePaintColors[paint]!),
          },
      ],
      'record': prefs?.getInt(_bestScoreKey) ?? 0,
      'tips': !(prefs?.containsKey(_tipsSeenKey) ?? false),
      // The app's own switches: sound effects and the vibration.
      'sound':
          prefs?.getBool(_citySoundKey) ??
          SoundEffectsService.instance.isEnabled,
      'haptics': HapticFeedbackHelper.enabled,
      'voice': voiceAvailable && voice,
      'voice_available': voiceAvailable,
      if (const bool.fromEnvironment('GAME_DEBUG'))
        'debug_perf': prefs?.getBool(_cityPerfKey) ?? false,
      'unlimited': unlimited,
      'available_runs': runs,
      'can_start': GameRunsService.canRide(premium: unlimited, runs: runs),
      'question_history': await GameQuestionHistoryService.instance.load(),
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
          'resume_text': appL10n.gameLobbyProgress(
            pending.answered,
            _runQuestions,
          ),
        'no_runs': appL10n.gameRunsNextIn(
          gameFuelCountdown(GameRunsService.instance.nextRefillAt),
        ),
      },
      'lang': lang,
    };
  }

  static String _hex(Color c) {
    String channel(double v) =>
        (v * 255).round().toRadixString(16).padLeft(2, '0');
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
    int token,
  ) async {
    final loading = AppLoadingOverlay.show(
      context,
      label: appL10n.gameReturning,
    );
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!context.mounted) return;
      final premium = ref.read(isPremiumProvider);
      final debugPerf = summary['debug_perf'];
      if (const bool.fromEnvironment('GAME_DEBUG') && debugPerf is bool) {
        await (await _prefs())?.setBool(_cityPerfKey, debugPerf);
      }
      final sound = summary['sound'];
      if (sound is bool) {
        await (await _prefs())?.setBool(_citySoundKey, sound);
      }
      final voice = summary['voice'];
      if (voice is bool && summary['voice_available'] == true) {
        await (await _prefs())?.setBool(_cityVoiceKey, voice);
      }
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

      final deltaCorrect = (correct - bookedCorrect).clamp(0, 10000);
      final unlocked = await GameGarageService.instance.recordCorrectAnswers(
        deltaCorrect,
      );
      if (deltaCorrect > 0) {
        ProgressSyncService.instance.scheduleSync();
      }
      // Keep the booked answer count before any dialog can interrupt this visit.
      if (finished) {
        await _clearPendingRun();
      } else {
        await _keepPendingRun(
          summary,
          runId: runId,
          score: score,
          correct: correct,
        );
      }
      if (!context.mounted) return;
      loading.close();
      if (!premium) {
        // Only fully presented in-game banners are acknowledged. A reward still
        // waiting in the queue when the ride closes keeps the reveal fallback.
        final notifiedRewards = summary['notified_rewards'] is List
            ? (summary['notified_rewards'] as List).whereType<String>().toSet()
            : const <String>{};
        for (final reward in unlocked) {
          final id = reward.isModel
              ? 'model:${reward.model}'
              : 'paint:${reward.paint}';
          if (notifiedRewards.contains(id)) continue;
          await _showReveal(context, reward);
          if (!context.mounted) return;
        }
      }

      // Left before the last question: the run waits for «Продолжить».
      if (!finished) return;
      if (!context.mounted) return;
      // Progress, rewards and pending-run cleanup are already durable. Keep the
      // launch guard until the optional request finishes, so a second game
      // cannot start while we are preparing this ride's results.
      final review = ref.read(reviewPromptServiceProvider);
      await WidgetsBinding.instance.endOfFrame;
      await review.onCompleted(
        readyToRequest: () async =>
            context.mounted &&
            (ModalRoute.of(context)?.isCurrent ?? false) &&
            (WidgetsBinding.instance.lifecycleState == null ||
                WidgetsBinding.instance.lifecycleState ==
                    AppLifecycleState.resumed),
      );
      if (!context.mounted) return;
      if (summary['native_result'] != true) {
        _releaseRun(token);
        await _showResult(context, ref, summary, best: best, record: record);
      }
    } finally {
      loading.close();
    }
  }

  /// The hub may offer resume even when all free runs have been spent.
  /// Reuse the same validated saved-run parser as the launch path.
  static Future<bool> hasPendingRun() async => await _pendingRun() != null;

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
        mistakes: [
          for (final m in (summary['mistakes'] as List? ?? const [])) '$m',
        ],
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
      await prefs.setString(
        _vehicleKey,
        gameVehicleIds.contains(id) ? id : GameGarageService.starter.id,
      );
      await prefs.setString(_paintKey, GameGarageService.normalizePaint(paint));
    } catch (_) {
      /* The car is kept for the next ride; a failed save is not a game error. */
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

  /// Milestones reveal either a model or one colour for the whole garage.
  static Future<void> _showReveal(
    BuildContext context,
    GameGarageReward reward,
  ) async {
    final soundEnabled =
        (await _prefs())?.getBool(_citySoundKey) ??
        SoundEffectsService.instance.isEnabled;
    if (!context.mounted) return;
    if (soundEnabled) SoundEffectsService.instance.playStreak();
    final colors = AppColors.of(context);
    final choose = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.cardBackground,
        surfaceTintColor: Colors.transparent,
        title: Text(
          reward.isModel
              ? appL10n.gameRevealTitle
              : appL10n.gameRevealPaintTitle,
        ),
        content: reward.isModel
            ? Text(gameCarName(reward.model!))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: gamePaintColors[reward.paint],
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.divider),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    appL10n.gameRevealPaintBody(gamePaintName(reward.paint!)),
                  ),
                ],
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(appL10n.gameRevealClose),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(appL10n.gameRevealChoose),
          ),
        ],
      ),
    );
    if (choose != true) return;
    final garage = GameGarageService.instance;
    final prefs = await _prefs();
    final savedId =
        prefs?.getString(_vehicleKey) ?? GameGarageService.starter.id;
    final savedPaint = GameGarageService.normalizePaint(
      prefs?.getString(_paintKey) ?? GameGarageService.starter.paint,
    );
    if (reward.isModel) {
      final paint = garage.ownedPaints.contains(savedPaint)
          ? savedPaint
          : GameGarageService.starter.paint;
      await _saveVehicle(reward.model!, paint);
    } else {
      final id = garage.ownedModels.contains(savedId)
          ? savedId
          : GameGarageService.starter.id;
      await _saveVehicle(id, reward.paint!);
    }
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
    final paint =
        prefs?.getString(_paintKey) ?? GameGarageService.starter.paint;
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

  static Future<Question?> _questionFor(
    WidgetRef ref,
    GameSituation situation,
  ) async {
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
