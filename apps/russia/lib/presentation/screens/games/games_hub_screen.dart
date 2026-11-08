import 'dart:async';
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
import 'package:pdd_app/presentation/screens/games/road_signs/road_signs_screen.dart';
import 'package:pdd_app/presentation/screens/games/games_hub_view.dart';
import 'package:pdd_app/presentation/widgets/premium_paywall_sheet.dart';
import 'package:pdd_app/presentation/widgets/sign_in_required_view.dart';

/// Gate every entry to the catalogue, including the standalone debug route.
/// The signed-in subtree is disposed on sign-out, along with its timers.
class GamesHubScreen extends ConsumerWidget {
  const GamesHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isAuthenticatedProvider)) {
      return SignInRequiredView(
        icon: Icons.sports_esports_rounded,
        title: appL10n.gameLockedTitle,
        body: appL10n.gameLockedHint,
      );
    }
    return const _SignedInGamesHubScreen();
  }
}

class _SignedInGamesHubScreen extends ConsumerStatefulWidget {
  const _SignedInGamesHubScreen();

  @override
  ConsumerState<_SignedInGamesHubScreen> createState() =>
      _GamesHubScreenState();
}

class _GamesHubScreenState extends ConsumerState<_SignedInGamesHubScreen>
    with WidgetsBindingObserver {
  int _runs = 0;
  bool _runsLoaded = false;
  bool _hasPendingRun = false;
  bool _openingCity = false;
  bool _openingPaywall = false;
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
    final saved = await GameLeaderboardService.instance.lastKnown();
    if (mounted && saved != null) {
      setState(() => _weekScore = saved.me?.score ?? 0);
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
    if (_openingCity) return;
    _openingCity = true;
    try {
      await _refreshRuns();
      if (!mounted) return;
      if (!GameRunsService.canRide(
        premium: ref.read(isPremiumProvider),
        runs: _runs,
      )) {
        await PremiumPaywallSheet.show(context);
        await _refreshRuns();
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
    } finally {
      _openingCity = false;
    }
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

  /// Free players reach a Premium game through the paywall that names it.
  /// Only a completed purchase or restore (`true`) continues into the game;
  /// an Android SBP browser handoff (`false`) or closing leaves the hub, and
  /// the card unlocks by itself once the payment is confirmed.
  Future<bool> _premiumUnlocked(String id, String title) async {
    if (!premiumGames.contains(id) || ref.read(isPremiumProvider)) return true;
    if (_openingPaywall) return false;
    _openingPaywall = true;
    try {
      final result = await PremiumPaywallSheet.show(context, lockedGame: title);
      return result == true && mounted;
    } finally {
      _openingPaywall = false;
    }
  }

  /// The Godot «Парковка» mini-game, the same availability rule as the crossroads.
  /// Availability comes first: a platform without the game sells nothing.
  Future<void> _openParking() async {
    if (!await GodotGame.available()) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(appL10n.gameUnavailable)));
      }
      return;
    }
    if (!mounted) return;
    if (!await _premiumUnlocked('parking', appL10n.gamesParkingTitle)) return;
    if (!mounted) return;
    HapticFeedbackHelper.tap();
    await GodotGame.playParking(context, ref);
    await _refreshRating();
  }

  Future<void> _openRoadSigns() async {
    await _open(context, const RoadSignsScreen());
  }

  Future<void> _openViolator() async {
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
    if (!await _premiumUnlocked('violator', appL10n.gamesViolatorTitle)) {
      return;
    }
    if (!mounted) return;
    HapticFeedbackHelper.tap();
    await GodotGame.playViolator(context, ref);
    await _refreshRating();
  }

  @override
  Widget build(BuildContext context) {
    return GamesHubView(
      weekScore: _weekScore,
      premium: ref.watch(isPremiumProvider),
      runsLoaded: _runsLoaded,
      hasPendingRun: _hasPendingRun,
      runs: _runs,
      refillAt: _runsLoaded ? GameRunsService.instance.nextRefillAt : null,
      onCity: _openCity,
      onTrafficController: _openTrafficController,
      onSigns: () => _open(context, const SignSwiperScreen()),
      onCrossroads: _openCrossroads,
      onParking: _openParking,
      onRoadSigns: _openRoadSigns,
      onViolator: _openViolator,
      onLeaderboard: () async {
        await GameLeaderboardSheet.show(context);
        await _refreshRating();
      },
      onRefilled: () => unawaited(_refreshRuns()),
    );
  }
}
