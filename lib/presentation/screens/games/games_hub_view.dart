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

/// Mini games only Premium players can open. Free players see the cover in black
/// and white with a Premium badge ("coming soon" is also dimmed, without the badge);
/// a tap opens the paywall naming the game, and a purchase goes straight into it.
/// The city looks the same while its free runs are used up, until they refill.
/// Test builds (`GAME_DEBUG`, see `build_dev.py`) open them without Premium.
const premiumGames = bool.fromEnvironment('GAME_DEBUG')
    ? <String>{}
    : <String>{'parking', 'violator'};

/// The hub's presentation, shared by the live screen and layout/state checks.
/// The city stays outside the scrolling mini-game catalogue, within thumb reach.
/// Large text keeps its natural size and gets a single-column catalogue.
class GamesHubView extends StatelessWidget {
  const GamesHubView({
    super.key,
    required this.weekScore,
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

  final int weekScore, runs;
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
                          // No free runs left: Premium only until they refill.
                          locked: waiting,
                          semanticDetails: [
                            if (waiting) appL10n.gameFuelEmptyTitle,
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
                          footer: !premium && runsLoaded
                              ? _RunsFooter(
                                  runs: runs,
                                  refillAt: refillAt,
                                  onRefilled: onRefilled,
                                )
                              : null,
                        );
                        Widget catalogue() => _MiniGamesCatalogue(
                          gap: gap,
                          premium: premium,
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
    required this.onTrafficController,
    required this.onSigns,
    required this.onCrossroads,
    required this.onParking,
    this.onRoadSigns,
    this.onViolator,
  });
  final double gap;
  final bool premium;
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
      titleSize: titleSize,
      onTap: onSigns,
    ),
    _HubCard(
      id: 'regulator',
      title: appL10n.gameTrafficControllerTitle,
      titleSize: titleSize,
      onTap: onTrafficController,
    ),
    _HubCard(
      id: 'crossroads',
      title: appL10n.gamesCrossroadsTitle,
      titleSize: titleSize,
      onTap: onCrossroads,
    ),
    _HubCard(
      id: 'road_signs',
      title: appL10n.gamesRoadSignsTitle,
      titleSize: titleSize,
      onTap: onRoadSigns,
    ),
    _HubCard(
      id: 'violator',
      title: appL10n.gamesViolatorTitle,
      titleSize: titleSize,
      onTap: onViolator,
      // Still "coming soon" for the stores; dev builds (GAME_DEBUG) can play it.
      comingSoon: !const bool.fromEnvironment('GAME_DEBUG'),
      locked: _locked('violator'),
    ),
    _HubCard(
      id: 'parking',
      title: appL10n.gamesParkingTitle,
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
    final status = comingSoon ? appL10n.gameSoonBadge : caption;
    final animation = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 260);
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
                // Closed games are black and white; colour returns with Premium
                // (or refilled runs) in the same fade as the badge.
                child: _Desaturated(
                  amount: comingSoon || premiumOnly ? 1 : 0,
                  opacity: comingSoon ? .5 : 1,
                  duration: animation,
                  child: _HubCover(id: id),
                ),
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
                    duration: animation,
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
                              Text(
                                status,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.25,
                                  fontWeight: FontWeight.w600,
                                  color: waiting ? colors.gold : foreground,
                                ),
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

/// The cover fading between colour (0) and black and white (1).
class _Desaturated extends StatelessWidget {
  const _Desaturated({
    required this.amount,
    required this.opacity,
    required this.duration,
    required this.child,
  });
  final double amount, opacity;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: amount),
    duration: duration,
    curve: Curves.easeOut,
    child: child,
    builder: (context, t, child) {
      final cover = t <= 0
          ? child!
          : ColorFiltered(colorFilter: _grey(t), child: child);
      return opacity < 1 ? Opacity(opacity: opacity, child: cover) : cover;
    },
  );

  /// Rec. 709 luminance mixed with the original colour by `t`.
  static ColorFilter _grey(double t) {
    final s = 1 - t;
    const r = .2126, g = .7152, b = .0722;
    return ColorFilter.matrix([
      r * t + s, g * t, b * t, 0, 0, //
      r * t, g * t + s, b * t, 0, 0, //
      r * t, g * t, b * t + s, 0, 0, //
      0, 0, 0, 1, 0,
    ]);
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
    this.onRefilled,
  });
  final int runs;
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
        if (runs > 0)
          _RunMetric(
            icon: Icons.local_gas_station_rounded,
            text: appL10n.gamesRunsFraction(runs, GameRunsService.maxRuns),
          ),
        if (refillAt != null) ...[
          if (runs > 0) const SizedBox(height: AppDimensions.spacingXS),
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
