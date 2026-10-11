import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/game_leaderboard_service.dart';
import 'package:pdd_app/data/services/game_runs_service.dart';
import 'package:pdd_app/data/services/progress_sync_service.dart';
import 'package:pdd_app/data/services/usage_reporter.dart';
import 'package:pdd_app/presentation/screens/game/controllers/game_controller.dart';
import 'package:pdd_app/presentation/screens/game/godot_web_screen.dart';
import 'package:pdd_app/presentation/screens/game/platform/godot_web_frame.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_fuel_widgets.dart';
import 'package:pdd_app/presentation/widgets/premium_paywall_sheet.dart';

/// «Живой город» on Godot (game_godot/): the game runs on its own screen with
/// its own HUD, questions and result. Android: a native screen (GodotGameActivity
/// in the process `:game`). Web: the same game in a frame on the site (godot/,
/// GodotWebScreen), when the site has the build. The app pays the run from the
/// stock before it starts and books the score when the player leaves.
///
/// Elsewhere (iOS, a site without the build) the WebView game (GameScreen) stays.
class GodotGame {
  GodotGame._();

  static const _channel = MethodChannel('pdd/godot_game');
  static const _bestScoreKey = 'game_best_score';
  static Future<bool>? _available;
  static Future<bool>? _webAvailable;
  static bool _running = false;

  static Future<bool> available() {
    if (kIsWeb) {
      return _webAvailable ??= GodotWebFrame.available();
    }
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(false);
    }
    return _available ??= _channel
        .invokeMethod<bool>('available')
        .then((v) => v ?? false)
        .catchError((_) => false);
  }

  /// One run: pay it (free players), open the game, book its score.
  static Future<void> play(BuildContext context, WidgetRef ref) async {
    if (_running) return;
    final unlimited = ref.read(isPremiumProvider);
    if (!unlimited) {
      await GameRunsService.instance.load();
      if (!await GameRunsService.instance.consume()) {
        if (context.mounted) _showRuns(context);
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
      json = await _start(context, ['--lang=$lang', if (dark) '--dark']);
    } on PlatformException {
      json = null;
    } finally {
      _running = false;
    }
    if (json == null) return;
    final summary = jsonDecode(json);
    if (summary is! Map) return;
    final score = (summary['score'] as num?)?.toInt() ?? 0;
    if (score <= 0) return;
    await GameLeaderboardService.instance.reportProgress(
      runId: GameLeaderboardService.newRunId(),
      delta: score,
      runScore: score,
      newRun: true,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      if (score > (prefs.getInt(_bestScoreKey) ?? 0)) {
        await prefs.setInt(_bestScoreKey, score);
      }
    } catch (_) {
      /* The rating has the score; the local best is a convenience. */
    }
    unawaited(ProgressSyncService.instance.syncWithServer());
  }

  /// Opens the game and waits for its summary (JSON), null if it did not end
  /// with one. Android: the native screen; web: the game's route.
  static Future<String?> _start(BuildContext context, List<String> args) {
    if (kIsWeb) {
      return Navigator.of(context).push<String>(
        MaterialPageRoute<String>(builder: (_) => GodotWebScreen(args: args)),
      );
    }
    return _channel.invokeMethod<String>('start', {'args': args});
  }

  static void _showRuns(BuildContext context) {
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
