import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdd_app/data/services/game_leaderboard_service.dart';
import 'package:pdd_app/data/services/game_runs_service.dart';
import 'package:pdd_app/presentation/screens/game/godot_game.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_leaderboard_sheet.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/games/sign_swiper/sign_swiper_screen.dart';
import 'package:pdd_app/presentation/screens/games/games_hub_view.dart';
import 'package:pdd_app/presentation/screens/game/controllers/game_controller.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_fuel_widgets.dart';
import 'package:pdd_app/presentation/widgets/premium_paywall_sheet.dart';

class GamesHubScreen extends ConsumerStatefulWidget {
  const GamesHubScreen({super.key});
  @override
  ConsumerState<GamesHubScreen> createState() => _GamesHubScreenState();
}

class _GamesHubScreenState extends ConsumerState<GamesHubScreen>
    with WidgetsBindingObserver {
  int _runs = 0;
  bool _runsLoaded = false;
  bool _hasPendingRun = false;
  int _cityBest = 0;
  int _weekScore = 0;
  Timer? _timer;
  Future<int>? _loadedRuns;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshRuns());
    unawaited(_refreshRating());
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _refreshRuns());
  }

  Future<void> _refreshRuns() async {
    await (_loadedRuns ??= GameRunsService.instance.load());
    final runs = GameRunsService.instance.refresh();
    final pending = await GodotGame.hasPendingRun();
    if (mounted) {
      setState(() {
        _runs = runs;
        _runsLoaded = true;
        _hasPendingRun = pending;
      });
    }
  }

  /// Сохранённые очки показываем сразу, затем свежие. Без связи остаются
  /// последние загруженные; без очков за неделю (или без входа) — 0.
  Future<void> _refreshRating() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await GameLeaderboardService.instance.lastKnown();
    if (mounted) {
      setState(() {
        _cityBest = prefs.getInt('game_best_score') ?? 0;
        if (saved != null) _weekScore = saved.me?.score ?? 0;
      });
    }
    final board = await GameLeaderboardService.instance.fetch();
    if (mounted && board != null) {
      setState(() => _weekScore = board.me?.score ?? 0);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshRuns());
      unawaited(_refreshRating());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _open(BuildContext context, Widget screen) async {
    HapticFeedbackHelper.tap();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));
    await _refreshRuns();
    await _refreshRating();
  }

  /// The Godot game on its own screen (Android, iOS, the site). A platform without the
  /// game in its build says so: the old WebView game is gone.
  Future<void> _openCity() async {
    await _refreshRuns();
    if (!mounted) return;
    if (!GameRunsService.canRide(
      premium: ref.read(isPremiumProvider),
      runs: _runs,
    )) {
      await _showRunsInfo();
      return;
    }
    if (!await GodotGame.available()) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(appL10n.gameUnavailable)));
      }
      return;
    }
    if (!mounted) return;
    HapticFeedbackHelper.tap();
    await GodotGame.play(context, ref);
    await _refreshRuns();
    await _refreshRating();
  }

  /// The Godot Regulator game on its own screen (Android, iOS, the site).
  /// A platform without the game in its build says so: the old WebView game is gone.
  Future<void> _openTrafficController() async {
    final avail = await GodotGame.available();
    if (!avail) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(appL10n.gameUnavailable)));
      }
      return;
    }
    if (!mounted) return;
    HapticFeedbackHelper.tap();
    await GodotGame.playRegulator(context, ref);
    await _refreshRating();
  }

  /// The Godot Crossroads Priority game on its own screen (Android, iOS, the site).
  /// A platform without the game in its build says so: the old WebView game is gone.
  Future<void> _openCrossroads() async {
    final avail = await GodotGame.available();
    if (!avail) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(appL10n.gameUnavailable)));
      }
      return;
    }
    if (!mounted) return;
    HapticFeedbackHelper.tap();
    await GodotGame.playCrossroads(context, ref);
    await _refreshRating();
  }

  Future<void> _openPremium() async {
    await PremiumPaywallSheet.show(context);
    await _refreshRuns();
  }

  Future<void> _showRunsInfo() async {
    await showGameRunsSheet(
      context,
      maxRuns: GameRunsService.maxRuns,
      questions: GameState.runQuestions,
      refillMinutes: GameRunsService.refillInterval.inMinutes,
      unlimited: ref.read(isPremiumProvider),
      runs: () => GameRunsService.instance.refresh(),
      nextRefillAt: () => GameRunsService.instance.nextRefillAt,
      onBuyPremium: () => unawaited(_openPremium()),
    );
    await _refreshRuns();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(progressImportsProvider, (_, next) {
      if (mounted && next.hasValue) {
        setState(
          () => _cityBest = ref
              .read(progressDataSourceProvider)
              .getGameBestScore(),
        );
      }
    });
    final traffic = ref.watch(trafficControllerProgressProvider);
    final signs = ref.watch(signSwiperProgressProvider);
    final crossroads = ref.watch(crossroadsPriorityProgressProvider);
    return GamesHubView(
      weekScore: _weekScore,
      cityBest: _cityBest,
      trafficBest: traffic.bestScore,
      signsBest: signs.bestScore,
      crossroadsBest: crossroads.bestScore,
      premium: ref.watch(isPremiumProvider),
      runsLoaded: _runsLoaded,
      hasPendingRun: _hasPendingRun,
      runs: _runs,
      refillAt: _runsLoaded ? GameRunsService.instance.nextRefillAt : null,
      onCity: _openCity,
      onTrafficController: _openTrafficController,
      onSigns: () => _open(context, const SignSwiperScreen()),
      onCrossroads: _openCrossroads,
      onLeaderboard: () async {
        await GameLeaderboardSheet.show(context);
        await _refreshRating();
      },
      onRunsInfo: _showRunsInfo,
      onPremium: _openPremium,
      onRefilled: () => unawaited(_refreshRuns()),
    );
  }
}
