import 'dart:math' as math;
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:pdd_app/data/services/game_leaderboard_service.dart';
import 'package:pdd_app/data/services/game_runs_service.dart';
import 'package:pdd_app/presentation/screens/game/game_screen.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_leaderboard_sheet.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/games/sign_swiper/sign_swiper_screen.dart';
import 'package:pdd_app/presentation/screens/games/traffic_controller/traffic_controller_screen.dart';
import 'package:pdd_app/presentation/screens/games/widgets/game_art.dart';

class GamesHubScreen extends ConsumerStatefulWidget {
  const GamesHubScreen({super.key});
  @override
  ConsumerState<GamesHubScreen> createState() => _GamesHubScreenState();
}

class _GamesHubScreenState extends ConsumerState<GamesHubScreen>
    with WidgetsBindingObserver {
  int _runs = GameRunsService.maxRuns;
  int _cityBest = 0;
  GameLeaderboardEntry? _me;
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
    if (mounted) setState(() => _runs = runs);
  }

  Future<void> _refreshRating() async {
    final prefs = await SharedPreferences.getInstance();
    final board = await GameLeaderboardService.instance.fetch();
    if (mounted) {
      setState(() {
        _cityBest = prefs.getInt('game_best_score') ?? 0;
        _me = board?.me;
      });
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

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final traffic = ref.watch(trafficControllerProgressProvider);
    final signs = ref.watch(signSwiperProgressProvider);
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: colors.background,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppDimensions.screenPadding,
          topInset + 16,
          AppDimensions.screenPadding,
          32,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppDimensions.spacingL),
            child: Row(
              children: [
                Text(
                  appL10n.navGames,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.searchFieldFill,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    appL10n.gamesBeta,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colors.secondaryText,
                    ),
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.gold,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    await GameLeaderboardSheet.show(context);
                    await _refreshRating();
                  },
                  icon: Icon(Icons.emoji_events_outlined, color: Colors.white),
                  label: Text(
                    _me == null
                        ? '—'
                        : NumberFormat.decimalPattern('ru').format(_me!.score),
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _GameCard(
            art: const CityArt(forCard: true),
            title: appL10n.gameCityTitle,
            status: ref.watch(isPremiumProvider)
                ? appL10n.gameRunsUnlimitedPill
                : appL10n.gamesRunsAvailable(_runs),
            statusIcon: Icons.local_gas_station_rounded,
            secondaryScore: _cityBest,
            onTap: () => _open(context, const GameScreen()),
          ),
          const SizedBox(height: AppDimensions.spacingL),
          _GameCard(
            art: const TrafficControllerArt(forCard: true),
            title: appL10n.gameTrafficControllerTitle,
            bestScore: traffic.bestScore,
            onTap: () => _open(context, const TrafficControllerScreen()),
          ),
          const SizedBox(height: AppDimensions.spacingL),
          _GameCard(
            art: const SignSwiperArt(forCard: true),
            title: appL10n.gameSignSwiperTitle,
            bestScore: signs.bestScore,
            onTap: () => _open(context, const SignSwiperScreen()),
          ),
          const SizedBox(height: AppDimensions.spacingL),
          _GameCard(
            art: const CrossroadsArt(forCard: true),
            title: appL10n.gameCrossroadsPriorityTitle,
          ),
          const SizedBox(height: AppDimensions.spacingL),
          _GameCard(
            art: const RoundaboutArt(forCard: true),
            title: appL10n.gameRoundaboutTitle,
          ),
        ],
      ),
    );
  }
}

/// Общая обложка: название и рекорд либо отметка ещё недоступной игры.
class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.art,
    required this.title,
    this.bestScore,
    this.onTap,
    this.status,
    this.statusIcon,
    this.secondaryScore,
  });

  final Widget art;
  final String title;
  final int? bestScore;
  final VoidCallback? onTap;
  final String? status;
  final IconData? statusIcon;
  final int? secondaryScore;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final radius = BorderRadius.circular(AppDimensions.cardRadius);
    final available = onTap != null;
    final status =
        this.status ??
        (bestScore == null
            ? appL10n.gameSoonBadge
            : appL10n.gameBestScore(bestScore!));
    final scaler = MediaQuery.textScalerOf(context);

    final card = Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Большой системный шрифт получает место, сохраняя обложку сверху.
            final height = math.max(
              constraints.maxWidth * 9 / 16,
              math.max(190.0, 112.0 + scaler.scale(22) * 2 + scaler.scale(13)),
            );
            return Semantics(
              button: true,
              enabled: available,
              label: '$title, $status',
              onTap: onTap,
              child: ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: radius,
                  child: SizedBox(
                    height: height,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColorFiltered(
                          colorFilter: available
                              ? const ColorFilter.mode(
                                  Colors.transparent,
                                  BlendMode.dst,
                                )
                              : const ColorFilter.matrix([
                                  .2126,
                                  .7152,
                                  .0722,
                                  0,
                                  0,
                                  .2126,
                                  .7152,
                                  .0722,
                                  0,
                                  0,
                                  .2126,
                                  .7152,
                                  .0722,
                                  0,
                                  0,
                                  0,
                                  0,
                                  0,
                                  1,
                                  0,
                                ]),
                          child: art,
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                available
                                    ? const Color(0x18091121)
                                    : const Color(0x18101010),
                                available
                                    ? const Color(0xD9091121)
                                    : const Color(0xD9101010),
                              ],
                              stops: [0.25, 0.45, 1],
                            ),
                          ),
                        ),
                        Positioned(
                          left: AppDimensions.spacingL,
                          right: AppDimensions.spacingL,
                          bottom: AppDimensions.spacingL,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      title,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        height: 1.12,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(
                                      height: AppDimensions.spacingS,
                                    ),
                                    Row(
                                      children: [
                                        Icon(
                                          statusIcon ??
                                              (available
                                                  ? Icons.emoji_events_rounded
                                                  : Icons.schedule_rounded),
                                          size: 16,
                                          color: available
                                              ? colors.gold
                                              : Colors.white,
                                        ),
                                        const SizedBox(
                                          width: AppDimensions.spacingXS,
                                        ),
                                        Flexible(
                                          child: Text(
                                            status,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              height: 1.2,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                        if (secondaryScore != null) ...[
                                          const SizedBox(width: 12),
                                          Icon(
                                            Icons.emoji_events_outlined,
                                            size: 16,
                                            color: colors.gold,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            NumberFormat.decimalPattern(
                                              'ru',
                                            ).format(secondaryScore!),
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (available) ...[
                                const SizedBox(width: AppDimensions.spacingM),
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 1),
                                  child: Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 24,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (available)
                          Material(
                            type: MaterialType.transparency,
                            child: InkWell(
                              onTap: onTap,
                              borderRadius: radius,
                              splashColor: Colors.white24,
                              highlightColor: Colors.white10,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    if (available) return RepaintBoundary(child: card);
    return Opacity(opacity: 0.55, child: RepaintBoundary(child: card));
  }
}
