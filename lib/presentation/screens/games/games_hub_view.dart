import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/data/services/game_runs_service.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_fuel_widgets.dart';

/// The hub's presentation, shared by the live screen and layout/state checks.
/// Small phones use the available height; large text keeps its natural size
/// and gets a scrollable, single-column layout.
class GamesHubView extends StatelessWidget {
  const GamesHubView({
    super.key,
    required this.weekScore,
    required this.cityBest,
    required this.trafficBest,
    required this.signsBest,
    required this.crossroadsBest,
    required this.premium,
    required this.runsLoaded,
    required this.hasPendingRun,
    required this.runs,
    this.refillAt,
    required this.onCity,
    required this.onTrafficController,
    required this.onSigns,
    required this.onCrossroads,
    required this.onLeaderboard,
    required this.onRunsInfo,
    required this.onPremium,
    this.onRefilled,
  });

  final int weekScore, cityBest, trafficBest, signsBest, crossroadsBest, runs;
  final bool premium, runsLoaded, hasPendingRun;
  final DateTime? refillAt;
  final VoidCallback onCity, onTrafficController, onSigns, onCrossroads;
  final VoidCallback onLeaderboard, onRunsInfo, onPremium;
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
                                  color: AppColors.white,
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
                        final compactHeight = box.maxHeight < 400;
                        final gap = compactHeight
                            ? AppDimensions.spacingS
                            : AppDimensions.spacingM;
                        final scaledTitle = MediaQuery.textScalerOf(
                          context,
                        ).scale(18);
                        final singleColumn =
                            scaledTitle > 24 || box.maxWidth < 280;
                        final wide =
                            !singleColumn &&
                            box.maxWidth >= 640 &&
                            box.maxWidth > box.maxHeight * 1.15;
                        final showWait =
                            !premium &&
                            runsLoaded &&
                            runs == 0 &&
                            !hasPendingRun;
                        final minCity =
                            (showWait
                                ? compactHeight
                                      ? 168.0
                                      : 176.0
                                : hasPendingRun
                                ? 136.0
                                : 120.0) +
                            math.max(0.0, scaledTitle - 18) * 8;
                        final available = box.maxHeight;
                        final double rowHeight = singleColumn
                            ? math.max(200.0, 110 + scaledTitle * 3)
                            : wide
                            ? math.max(94.0, (available - gap) / 2)
                            : ((available - gap * 2) * .35)
                                  .clamp(
                                    compactHeight ? 90.0 : 94.0,
                                    math.max(
                                      compactHeight ? 90.0 : 94.0,
                                      (available - gap * 2 - minCity) / 2,
                                    ),
                                  )
                                  .toDouble();
                        final cityHeight = wide
                            ? rowHeight * 2 + gap
                            : math.max(
                                minCity,
                                available - rowHeight * 2 - gap * 2,
                              );
                        final tiles = [
                          _HubCard(
                            id: 'parking',
                            title: appL10n.gamesParkingTitle,
                            caption: appL10n.gameSoonBadge,
                          ),
                          _HubCard(
                            id: 'signs',
                            title: appL10n.gamesSignsTitle,
                            bestScore: signsBest,
                            onTap: onSigns,
                          ),
                          _HubCard(
                            id: 'regulator',
                            title: appL10n.gameTrafficControllerTitle,
                            bestScore: trafficBest,
                            titleSize: box.maxWidth < 320 ? 15 : 18,
                            onTap: onTrafficController,
                          ),
                          _HubCard(
                            id: 'crossroads',
                            title: appL10n.gamesCrossroadsTitle,
                            titleSize: box.maxWidth < 320 ? 15 : 18,
                            bestScore: crossroadsBest,
                            onTap: onCrossroads,
                          ),
                        ];
                        Widget row(int first) => SizedBox(
                          height: rowHeight,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: tiles[first]),
                              SizedBox(width: gap),
                              Expanded(child: tiles[first + 1]),
                            ],
                          ),
                        );
                        final city = _HubCard(
                          id: 'city',
                          title: appL10n.gameCityTitle,
                          bestScore: cityBest,
                          onTap: onCity,
                          featured: true,
                          hideStatus: !premium && !hasPendingRun,
                          caption: hasPendingRun
                              ? appL10n.gamesResumeRide
                              : showWait
                              ? appL10n.gameFuelEmptyTitle
                              : null,
                          footer: !premium && runsLoaded
                              ? _RunsFooter(
                                  runs: runs,
                                  bestScore: hasPendingRun ? 0 : cityBest,
                                  refillAt: refillAt,
                                  waiting: showWait,
                                  onInfo: onRunsInfo,
                                  onPremium: onPremium,
                                  onRefilled: onRefilled,
                                )
                              : null,
                        );
                        return SingleChildScrollView(
                          key: const ValueKey('games-scroll'),
                          child: singleColumn
                              ? Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (final tile in tiles) ...[
                                      SizedBox(height: rowHeight, child: tile),
                                      SizedBox(height: gap),
                                    ],
                                    SizedBox(
                                      height: math.max(
                                        220 + scaledTitle * 5,
                                        cityHeight,
                                      ),
                                      child: city,
                                    ),
                                  ],
                                )
                              : wide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 6,
                                      child: Column(
                                        children: [
                                          row(0),
                                          SizedBox(height: gap),
                                          row(2),
                                        ],
                                      ),
                                    ),
                                    SizedBox(width: gap),
                                    Expanded(
                                      flex: 5,
                                      child: SizedBox(
                                        height: cityHeight,
                                        child: city,
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  children: [
                                    row(0),
                                    SizedBox(height: gap),
                                    row(2),
                                    SizedBox(height: gap),
                                    SizedBox(height: cityHeight, child: city),
                                  ],
                                ),
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

class _HubCard extends StatelessWidget {
  const _HubCard({
    required this.id,
    required this.title,
    this.bestScore,
    this.caption,
    this.onTap,
    this.featured = false,
    this.hideStatus = false,
    this.titleSize = 18,
    this.footer,
  });

  final String id, title;
  final int? bestScore;
  final String? caption;
  final VoidCallback? onTap;
  final bool featured, hideStatus;
  final double titleSize;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final enabled = onTap != null;
    final foreground = AppColors.white.withValues(alpha: enabled ? 1 : .6);
    final record = bestScore != null && bestScore! > 0;
    final status =
        caption ?? (record ? _number(context, bestScore!) : appL10n.gamesPlay);
    final semanticStatus = record && caption == null
        ? appL10n.gamesRecordScore(status)
        : status;
    final radius = BorderRadius.circular(AppDimensions.cardRadius);
    return RepaintBoundary(
      child: Semantics(
        key: ValueKey('games-card-$id'),
        button: true,
        enabled: enabled,
        label: '$title, $semanticStatus',
        onTap: onTap,
        // The image is decorative; footer actions retain their own semantics.
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ExcludeSemantics(child: _HubCover(id: id)),
              if (!enabled)
                ColoredBox(color: colors.background.withValues(alpha: .30)),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, .35, 1],
                    colors: [
                      Colors.transparent,
                      featured ? const Color(0x78000A15) : Colors.transparent,
                      const Color(0xEB000A15),
                    ],
                  ),
                ),
              ),
              if (enabled)
                Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: onTap,
                    excludeFromSemantics: true,
                    splashColor: Colors.white24,
                    highlightColor: Colors.white10,
                  ),
                ),
              // Text passes taps through to the card; the footer has separate,
              // comfortably sized targets for runs and the Premium action.
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: featured
                      ? 16
                      : titleSize < 18
                      ? 8
                      : 12,
                  vertical: featured ? 16 : 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IgnorePointer(
                      child: ExcludeSemantics(
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
                                    style: TextStyle(
                                      fontSize: featured ? 24 : titleSize,
                                      height: 1.12,
                                      fontWeight: FontWeight.w700,
                                      color: foreground,
                                    ),
                                  ),
                                  if (!hideStatus) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        if (record && caption == null) ...[
                                          Icon(
                                            Icons.emoji_events_rounded,
                                            size: 14,
                                            color: colors.gold,
                                          ),
                                          const SizedBox(width: 3),
                                        ],
                                        Flexible(
                                          child: Text(
                                            status,
                                            style: TextStyle(
                                              fontSize: 13,
                                              height: 1.2,
                                              fontWeight: FontWeight.w600,
                                              color: record && caption == null
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
                            if (featured) ...[
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                size: 26,
                                color: AppColors.white,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (footer != null) ...[const SizedBox(height: 6), footer!],
                  ],
                ),
              ),
            ],
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
      final nativeWidth = wide ? 1072 : 516;
      final aspect = wide ? 1072 / 560 : 516 / 652;
      final pixels =
          math.max(box.maxWidth, box.maxHeight * aspect) *
          MediaQuery.devicePixelRatioOf(context);
      final decodeWidth = math.min(
        nativeWidth,
        pixels <= 258
            ? 258
            : pixels <= 516
            ? 516
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
    required this.bestScore,
    required this.refillAt,
    required this.waiting,
    required this.onInfo,
    required this.onPremium,
    this.onRefilled,
  });
  final int runs, bestScore;
  final DateTime? refillAt;
  final bool waiting;
  final VoidCallback onInfo, onPremium;
  final VoidCallback? onRefilled;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          key: const ValueKey('games-runs-info'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.white,
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.zero,
            minimumSize: const Size(48, 48),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: onInfo,
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 4,
            children: [
              if (bestScore > 0)
                Semantics(
                  label: appL10n.gamesRecordScore(_number(context, bestScore)),
                  excludeSemantics: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.emoji_events_rounded,
                        size: 14,
                        color: colors.gold,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _number(context, bestScore),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.gold,
                        ),
                      ),
                    ],
                  ),
                ),
              if (runs > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_gas_station_rounded,
                      size: 16,
                      color: colors.gold,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      appL10n.gamesRunsFraction(runs, GameRunsService.maxRuns),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              if (refillAt != null)
                _RefillCountdown(at: refillAt!, onRefilled: onRefilled),
            ],
          ),
        ),
        if (waiting)
          FilledButton.icon(
            key: const ValueKey('games-premium'),
            onPressed: onPremium,
            style: FilledButton.styleFrom(
              backgroundColor: colors.gold,
              foregroundColor: AppColors.primaryText,
              minimumSize: const Size.fromHeight(48),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
              ),
            ),
            icon: const Icon(Icons.all_inclusive_rounded, size: 20),
            label: Text(
              appL10n.gamesUnlimitedAction,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryText,
              ),
            ),
          ),
      ],
    );
  }
}

/// Only the small countdown repaints each second, not the five cover images.
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
