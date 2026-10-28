import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/data/services/game_runs_service.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_fuel_widgets.dart';

/// Mini games that are not ready for release: their cards are not shown. The screens,
/// progress and leaderboards stay in the code; add a card id here to hide a game.
const hiddenGames = <String>{};

/// Mini games only Premium players can open. Free players still see the full
/// colour cover with a Premium badge (grey is reserved for "coming soon"); a tap
/// opens the paywall naming the game, and a purchase goes straight into it.
const premiumGames = <String>{'parking', 'violator'};

/// The hub's presentation, shared by the live screen and layout/state checks.
/// The city stays outside the scrolling mini-game catalogue, within thumb reach.
/// Large text keeps its natural size and gets a single-column catalogue.
class GamesHubView extends StatelessWidget {
  const GamesHubView({
    super.key,
    required this.weekScore,
    required this.cityBest,
    required this.trafficBest,
    required this.signsBest,
    required this.crossroadsBest,
    required this.parkingBest,
    this.roadSignsBest = 0,
    this.violatorBest = 0,
    required this.premium,
    required this.runsLoaded,
    required this.hasPendingRun,
    required this.runs,
    this.refillAt,
    required this.onCity,
    required this.onTrafficController,
    required this.onSigns,
    required this.onCrossroads,
    required this.onParking,
    this.onRoadSigns,
    this.onViolator,
    required this.onLeaderboard,
    this.onRefilled,
  });

  final int weekScore, cityBest, trafficBest, signsBest, crossroadsBest, runs;
  final int parkingBest, roadSignsBest, violatorBest;
  final bool premium, runsLoaded, hasPendingRun;
  final DateTime? refillAt;
  final VoidCallback onCity,
      onTrafficController,
      onSigns,
      onCrossroads,
      onParking;
  final VoidCallback? onRoadSigns, onViolator;
  final VoidCallback onLeaderboard;
  final VoidCallback? onRefilled;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final shortScreen = MediaQuery.sizeOf(context).height < 650;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppDimensions.screenPadding,
                shortScreen ? AppDimensions.spacingS : AppDimensions.spacingM,
                AppDimensions.screenPadding,
                shortScreen ? AppDimensions.spacingS : AppDimensions.spacingL,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          appL10n.navGames,
                          style: TextStyle(
                            fontSize: 26,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            color: colors.primaryText,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppDimensions.spacingM),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: math.min(
                            240,
                            MediaQuery.sizeOf(context).width * .5,
                          ),
                        ),
                        child: Tooltip(
                          message: appL10n.gameLeaderboard,
                          child: Semantics(
                            label: appL10n.gamesWeeklyScore(weekScore),
                            child: FilledButton.icon(
                              key: const ValueKey('games-leaderboard'),
                              style: FilledButton.styleFrom(
                                backgroundColor: colors.gold,
                                foregroundColor: AppColors.white,
                                minimumSize: const Size(64, 48),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                              ),
                              onPressed: onLeaderboard,
                              icon: const Icon(
                                Icons.emoji_events_outlined,
                                size: 22,
                              ),
                              label: Text(
                                _number(context, weekScore),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                    height: shortScreen
                        ? AppDimensions.spacingS
                        : AppDimensions.spacingL,
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final gap = box.maxHeight < 400
                            ? AppDimensions.spacingS
                            : AppDimensions.spacingM;
                        final wide =
                            box.maxWidth >= 480 &&
                            box.maxWidth > box.maxHeight * 1.15;
                        final compactCity =
                            wide &&
                            box.maxHeight < 280 &&
                            MediaQuery.textScalerOf(context).scale(24) > 28;
                        final waiting =
                            !premium &&
                            runsLoaded &&
                            !GameRunsService.canRide(
                              premium: premium,
                              runs: runs,
                            );
                        final caption = waiting
                            ? appL10n.gamesUnlimitedAction
                            : hasPendingRun
                            ? appL10n.gamesResumeRide
                            : null;
                        final city = _HubCard(
                          id: 'city',
                          title: appL10n.gameCityTitle,
                          caption: caption,
                          onTap: onCity,
                          featured: true,
                          compact: compactCity,
                          waiting: waiting,
                          semanticDetails: [
                            if (waiting) appL10n.gameFuelEmptyTitle,
                            if (cityBest > 0 && !hasPendingRun)
                              appL10n.gamesRecordScore(
                                _number(context, cityBest),
                              ),
                            if (!premium && runsLoaded && runs > 0)
                              appL10n.gamesRunsFraction(
                                runs,
                                GameRunsService.maxRuns,
                              ),
                            if (!premium && runsLoaded && refillAt != null)
                              appL10n.gamesRefillIn(
                                gameFuelCountdown(refillAt),
                              ),
                          ].join(', '),
                          footer:
                              (!premium && runsLoaded) ||
                                  (cityBest > 0 && !hasPendingRun)
                              ? _RunsFooter(
                                  runs: !premium && runsLoaded ? runs : 0,
                                  bestScore: hasPendingRun ? 0 : cityBest,
                                  refillAt: !premium && runsLoaded
                                      ? refillAt
                                      : null,
                                  onRefilled: onRefilled,
                                )
                              : null,
                        );
                        Widget catalogue() => _MiniGamesCatalogue(
                          gap: gap,
                          premium: premium,
                          trafficBest: trafficBest,
                          signsBest: signsBest,
                          crossroadsBest: crossroadsBest,
                          parkingBest: parkingBest,
                          roadSignsBest: roadSignsBest,
                          violatorBest: violatorBest,
                          onTrafficController: onTrafficController,
                          onSigns: onSigns,
                          onCrossroads: onCrossroads,
                          onParking: onParking,
                          onRoadSigns: onRoadSigns,
                          onViolator: onViolator,
                        );
                        if (wide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: compactCity ? 4 : 6,
                                child: catalogue(),
                              ),
                              SizedBox(width: gap),
                              Expanded(flex: compactCity ? 7 : 5, child: city),
                            ],
                          );
                        }
                        // The card sizes itself to its text. Only the catalogue
                        // scrolls, even when the device's font size is enlarged.
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: catalogue()),
                            SizedBox(height: gap),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: (box.maxHeight * .30).clamp(
                                  156,
                                  210,
                                ),
                              ),
                              child: city,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _number(BuildContext context, int score) => NumberFormat.decimalPattern(
  Localizations.localeOf(context).toLanguageTag(),
).format(score);

/// The mini-game catalogue scrolls without displacing the city.
class _MiniGamesCatalogue extends StatelessWidget {
  const _MiniGamesCatalogue({
    required this.gap,
    required this.premium,
    required this.trafficBest,
    required this.signsBest,
    required this.crossroadsBest,
    required this.parkingBest,
    this.roadSignsBest = 0,
    this.violatorBest = 0,
    required this.onTrafficController,
    required this.onSigns,
    required this.onCrossroads,
    required this.onParking,
    this.onRoadSigns,
    this.onViolator,
  });
  final double gap;
  final bool premium;
  final int trafficBest,
      signsBest,
      crossroadsBest,
      parkingBest,
      roadSignsBest,
      violatorBest;
  final VoidCallback onTrafficController, onSigns, onCrossroads, onParking;
  final VoidCallback? onRoadSigns, onViolator;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scaledTitle = MediaQuery.textScalerOf(context).scale(18);
      final columns = scaledTitle > 24 || box.maxWidth < 280
          ? 1
          : box.maxWidth >= 600
          ? 3
          : 2;
      final tiles = _tiles(
        titleSize: columns > 1 && box.maxWidth < 320 ? 15.0 : 18.0,
      ).where((tile) => !hiddenGames.contains(tile.id)).toList();
      final rows = (tiles.length / columns).ceil();
      final rowHeight = math.max(
        columns == 1
            ? math.max(110 + scaledTitle * 3, box.maxWidth * .9)
            : 118.0,
        (box.maxHeight - gap * (rows - 1)) / rows,
      );
      return _CatalogueScroll(
        overflow: rowHeight * rows + gap * (rows - 1) > box.maxHeight + .5,
        child: Column(
          children: [
            for (var row = 0; row < rows; row++) ...[
              if (row > 0) SizedBox(height: gap),
              SizedBox(
                height: rowHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var col = 0; col < columns; col++) ...[
                      if (col > 0) SizedBox(width: gap),
                      Expanded(
                        child: row * columns + col < tiles.length
                            ? tiles[row * columns + col]
                            : const SizedBox(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    },
  );

  List<_HubCard> _tiles({required double titleSize}) => [
    _HubCard(
      id: 'signs',
      title: appL10n.gamesSignsTitle,
      bestScore: signsBest,
      titleSize: titleSize,
      onTap: onSigns,
    ),
    _HubCard(
      id: 'regulator',
      title: appL10n.gameTrafficControllerTitle,
      bestScore: trafficBest,
      titleSize: titleSize,
      onTap: onTrafficController,
    ),
    _HubCard(
      id: 'crossroads',
      title: appL10n.gamesCrossroadsTitle,
      bestScore: crossroadsBest,
      titleSize: titleSize,
      onTap: onCrossroads,
    ),
    _HubCard(
      id: 'road_signs',
      title: appL10n.gamesRoadSignsTitle,
      bestScore: roadSignsBest,
      titleSize: titleSize,
      onTap: onRoadSigns,
    ),
    _HubCard(
      id: 'violator',
      title: appL10n.gamesViolatorTitle,
      bestScore: violatorBest,
      titleSize: titleSize,
      onTap: onViolator,
      // Still "coming soon" for the stores; dev builds (GAME_DEBUG) can play it.
      comingSoon: !const bool.fromEnvironment('GAME_DEBUG'),
      locked: _locked('violator'),
    ),
    _HubCard(
      id: 'parking',
      title: appL10n.gamesParkingTitle,
      bestScore: parkingBest,
      titleSize: titleSize,
      onTap: onParking,
      locked: _locked('parking'),
    ),
  ];

  bool _locked(String id) => !premium && premiumGames.contains(id);
}

class _CatalogueScroll extends StatefulWidget {
  const _CatalogueScroll({required this.overflow, required this.child});
  final bool overflow;
  final Widget child;

  @override
  State<_CatalogueScroll> createState() => _CatalogueScrollState();
}

class _CatalogueScrollState extends State<_CatalogueScroll> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: _controller,
    thumbVisibility: widget.overflow,
    thickness: 3,
    child: SingleChildScrollView(
      key: const ValueKey('games-scroll'),
      controller: _controller,
      child: widget.child,
    ),
  );
}

class _HubCard extends StatelessWidget {
  const _HubCard({
    required this.id,
    required this.title,
    this.bestScore,
    this.caption,
    this.onTap,
    this.featured = false,
    this.waiting = false,
    this.comingSoon = false,
    this.locked = false,
    this.compact = false,
    this.semanticDetails = '',
    this.titleSize = 18,
    this.footer,
  });

  final String id, title;
  final int? bestScore;
  final String? caption;
  final VoidCallback? onTap;
  final bool featured, waiting, comingSoon, locked, compact;
  final String semanticDetails;
  final double titleSize;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final launch = comingSoon ? null : onTap;
    final enabled = launch != null;
    // "Coming soon" outranks the badge: an unreleased game is not for sale.
    final premiumOnly = locked && !comingSoon;
    const foreground = AppColors.white;
    final record = !comingSoon && bestScore != null && bestScore! > 0;
    final status = comingSoon
        ? appL10n.gameSoonBadge
        : caption ??
              (record
                  ? appL10n.gamesRecordScore(_number(context, bestScore!))
                  : null);
    final radius = BorderRadius.circular(AppDimensions.cardRadius);
    return RepaintBoundary(
      child: Semantics(
        key: ValueKey('games-card-$id'),
        button: true,
        enabled: enabled,
        label: [
          title,
          if (premiumOnly) appL10n.gamesPremiumBadge,
          ?status,
          if (semanticDetails.isNotEmpty) semanticDetails,
        ].join(', '),
        hint: premiumOnly ? appL10n.gamesPremiumHint : null,
        excludeSemantics: true,
        onTap: launch,
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            alignment: Alignment.bottomLeft,
            fit: featured ? StackFit.loose : StackFit.expand,
            children: [
              Positioned.fill(
                child: comingSoon
                    ? Opacity(
                        opacity: .5,
                        child: ColorFiltered(
                          colorFilter: const ColorFilter.matrix([
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
                          child: _HubCover(id: id),
                        ),
                      )
                    : _HubCover(id: id),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0, .4, 1],
                      colors: [
                        Colors.transparent,
                        featured
                            ? const Color(0x66000A15)
                            : const Color(0x14000A15),
                        const Color(0xF0000A15),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: AppDimensions.spacingS,
                right: AppDimensions.spacingS,
                child: IgnorePointer(
                  // The badge leaves with a short fade once Premium arrives.
                  child: AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: animation, child: child),
                    ),
                    child: premiumOnly
                        ? const _PremiumBadge()
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
              if (enabled)
                Positioned.fill(
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      onTap: launch,
                      excludeFromSemantics: true,
                      splashColor: Colors.white24,
                      highlightColor: Colors.white10,
                    ),
                  ),
                ),
              IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: featured
                        ? AppDimensions.spacingL
                        : titleSize < 18
                        ? AppDimensions.spacingS
                        : AppDimensions.spacingM,
                    vertical: compact
                        ? AppDimensions.spacingS
                        : featured
                        ? AppDimensions.spacingL
                        : AppDimensions.spacingM,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: featured
                        ? MainAxisSize.min
                        : MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ExcludeSemantics(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: featured
                                    ? (compact ? 20 : 24)
                                    : titleSize,
                                height: 1.15,
                                fontWeight: FontWeight.w700,
                                color: foreground,
                              ),
                            ),
                            if (status != null) ...[
                              const SizedBox(height: AppDimensions.spacingXS),
                              Row(
                                children: [
                                  if (record && caption == null) ...[
                                    Icon(
                                      Icons.emoji_events_rounded,
                                      size: 14,
                                      color: colors.gold,
                                    ),
                                    const SizedBox(
                                      width: AppDimensions.spacingXS,
                                    ),
                                  ],
                                  Flexible(
                                    child: Text(
                                      status,
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.25,
                                        fontWeight: FontWeight.w600,
                                        color:
                                            waiting ||
                                                (record && caption == null)
                                            ? colors.gold
                                            : foreground,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (!compact) ?footer,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A solid amber chip: the hub's upsell colour, readable on any cover photo.
/// Text grows with the system size only up to a point; readers get the label
/// from the card itself.
class _PremiumBadge extends StatelessWidget {
  const _PremiumBadge();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: ExcludeSemantics(
        child: DecoratedBox(
          key: const ValueKey('games-premium-badge'),
          decoration: BoxDecoration(
            color: colors.premiumAmber,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_rounded,
                  size: 14,
                  color: AppColors.primaryText,
                ),
                const SizedBox(width: 4),
                Text(
                  appL10n.gamesPremiumBadge,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HubCover extends StatelessWidget {
  const _HubCover({required this.id});
  final String id;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final wide = id == 'city';
      final nativeWidth = wide ? 1072 : 640;
      final aspect = wide ? 1072 / 560 : 1.0;
      final pixels =
          math.max(box.maxWidth, box.maxHeight * aspect) *
          MediaQuery.devicePixelRatioOf(context);
      final decodeWidth = math.min(
        nativeWidth,
        pixels <= 320
            ? 320
            : pixels <= 640
            ? 640
            : 1072,
      );
      return Image.asset(
        'assets/images/games/hub_$id.webp',
        fit: BoxFit.cover,
        cacheWidth: decodeWidth,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
      );
    },
  );
}

class _RunsFooter extends StatelessWidget {
  const _RunsFooter({
    required this.runs,
    required this.refillAt,
    required this.bestScore,
    this.onRefilled,
  });
  final int runs, bestScore;
  final DateTime? refillAt;
  final VoidCallback? onRefilled;

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('games-runs-status'),
    padding: const EdgeInsets.only(top: AppDimensions.spacingS),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: AppDimensions.spacingM,
          runSpacing: AppDimensions.spacingXS,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (bestScore > 0)
              _RunMetric(
                icon: Icons.emoji_events_rounded,
                text: appL10n.gamesRecordScore(_number(context, bestScore)),
              ),
            if (runs > 0)
              _RunMetric(
                icon: Icons.local_gas_station_rounded,
                text: appL10n.gamesRunsFraction(runs, GameRunsService.maxRuns),
              ),
          ],
        ),
        if (refillAt != null) ...[
          if (runs > 0 || bestScore > 0)
            const SizedBox(height: AppDimensions.spacingXS),
          _RefillCountdown(at: refillAt!, onRefilled: onRefilled),
        ],
      ],
    ),
  );
}

class _RunMetric extends StatelessWidget {
  const _RunMetric({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: AppColors.of(context).gold),
      const SizedBox(width: 5),
      Flexible(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            height: 1.25,
            fontWeight: FontWeight.w600,
            color: AppColors.white,
          ),
        ),
      ),
    ],
  );
}

/// Only the small countdown repaints each second, not the cover images.
class _RefillCountdown extends StatefulWidget {
  const _RefillCountdown({required this.at, this.onRefilled});
  final DateTime at;
  final VoidCallback? onRefilled;
  @override
  State<_RefillCountdown> createState() => _RefillCountdownState();
}

class _RefillCountdownState extends State<_RefillCountdown> {
  Timer? _timer;
  bool _notified = false;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!DateTime.now().isBefore(widget.at) && !_notified) {
        _notified = true;
        widget.onRefilled?.call();
      }
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant _RefillCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.at != widget.at) _notified = false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: Text(
      appL10n.gamesRefillIn(gameFuelCountdown(widget.at)),
      style: const TextStyle(
        fontSize: 12,
        height: 1.2,
        color: AppColors.white,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    ),
  );
}
