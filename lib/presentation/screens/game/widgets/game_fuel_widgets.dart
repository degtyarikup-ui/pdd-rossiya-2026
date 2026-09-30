import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Runs in stock: a flag with one bar per run, or the infinity sign for
/// premium players.
class GameFuelGauge extends StatelessWidget {
  final int fuel;
  final int maxFuel;
  final bool unlimited;

  const GameFuelGauge({
    super.key,
    required this.fuel,
    required this.maxFuel,
    required this.unlimited,
    this.vertical = false,
  });

  /// HUD layout: the pump on top, the bars stacked upward beneath it.
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final low = !unlimited && fuel <= 0;
    final tint = low ? colors.red : colors.accent;
    return Semantics(
      label: unlimited
          ? appL10n.gameFuelUnlimited
          : '${appL10n.gameFuel}: $fuel / $maxFuel',
      // Design: the fuel pump and one bar per unit, straight on the map.
      // Unlimited fuel shows a full tank.
      child: Flex(
        direction: vertical ? Axis.vertical : Axis.horizontal,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Runs in stock: a finish flag and one bar per run.
          Icon(
            Icons.sports_score_rounded,
            key: const ValueKey('hud-fuel'),
            size: 24,
            color: tint,
          ),
          const SizedBox(width: 8, height: 8),
          // Unlimited fuel: the infinity sign instead of the bars.
          if (unlimited)
            Text(
              '∞',
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 24,
                height: 1,
                fontWeight: FontWeight.w800,
                color: tint,
              ),
            )
          else
            for (var i = 0; i < maxFuel; i++)
              Container(
                width: vertical ? 16 : 5,
                height: vertical ? 5 : 16,
                margin: vertical
                    ? EdgeInsets.only(bottom: i == maxFuel - 1 ? 0 : 4)
                    : EdgeInsets.only(right: i == maxFuel - 1 ? 0 : 4),
                decoration: BoxDecoration(
                  // Vertical: filled from the bottom up, like a tank.
                  color: (vertical ? maxFuel - 1 - i : i) < fuel
                      ? tint
                      : colors.gray.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(38),
                ),
              ),
        ],
      ),
    );
  }
}

/// "Out of fuel": the countdown to the next unit and the premium pitch.
/// On the game screen it is the bottom card; in the results dialog
/// (`compact`) only the pitch is shown, the countdown lives in the header.
class GameFuelEmptyPanel extends StatefulWidget {
  final DateTime? refillAt;
  final VoidCallback onBuyPremium;
  final bool compact;

  /// Called once when the countdown reaches zero: the tank is full again.
  final VoidCallback? onRefilled;

  const GameFuelEmptyPanel({
    super.key,
    required this.refillAt,
    required this.onBuyPremium,
    this.compact = false,
    this.onRefilled,
  });

  @override
  State<GameFuelEmptyPanel> createState() => _GameFuelEmptyPanelState();
}

class _GameFuelEmptyPanelState extends State<GameFuelEmptyPanel> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!widget.compact) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final at = widget.refillAt;
        if (at == null || !DateTime.now().isBefore(at)) {
          _timer?.cancel();
          widget.onRefilled?.call();
        }
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final pitch = GameFuelPremiumPitch(onBuyPremium: widget.onBuyPremium);
    if (widget.compact) return pitch;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GameFuelEmptyIcon(size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appL10n.gameFuelEmptyTitle,
                      style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: colors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      appL10n.gameFuelRefillIn(
                        gameFuelCountdown(widget.refillAt),
                      ),
                      style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          pitch,
        ],
      ),
    );
  }
}

/// "M:SS" until [at]; "0:00" when it has passed or is unknown.
String gameFuelCountdown(DateTime? at) {
  if (at == null) return '0:00';
  final left = at.difference(DateTime.now());
  if (left.isNegative) return '0:00';
  final m = left.inMinutes, s = left.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// The red pump in a tinted circle, used wherever the tank is empty.
class GameFuelEmptyIcon extends StatelessWidget {
  final double size;
  const GameFuelEmptyIcon({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.red.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.sports_score_rounded,
        color: colors.red,
        size: size * 0.55,
      ),
    );
  }
}

/// The pitch: a warm gold panel, the infinity sign and one button.
class GameFuelPremiumPitch extends StatelessWidget {
  final VoidCallback onBuyPremium;
  const GameFuelPremiumPitch({super.key, required this.onBuyPremium});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.gold.withValues(alpha: 0.22),
            colors.gold.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '∞',
                style: TextStyle(
                  fontSize: 28,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: colors.gold,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  appL10n.gameFuelPremiumPitch,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 14,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: onBuyPremium,
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.gold,
              foregroundColor: Colors.white,
              elevation: 0,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
              ),
            ),
            child: Text(
              appL10n.gameFuelBuyPremium,
              style: const TextStyle(
                fontFamily: 'Onest',
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Garage: the runs in stock as a plain white pill («Заезды 2 из 3»); a tap
/// explains what a run is and when the next one comes.
class GameRunsPill extends StatelessWidget {
  final int runs;
  final int maxRuns;
  final bool unlimited;
  final VoidCallback? onTap;

  const GameRunsPill({
    super.key,
    required this.runs,
    required this.maxRuns,
    required this.unlimited,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final empty = !unlimited && runs <= 0;
    final text = unlimited
        ? appL10n.gameRunsUnlimitedPill
        : appL10n.gameRunsPill(runs, maxRuns);
    return Semantics(
      button: onTap != null,
      label: text,
      child: Material(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(90),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('lobby-runs'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
            child: SizedBox(
              height: 36,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.sports_score_rounded,
                    size: 20,
                    color: empty ? colors.red : colors.accent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    text,
                    style: TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      color: empty ? colors.red : colors.primaryText,
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

/// What a run is, how many are in stock and when the next one comes (a
/// live countdown), with the way to unlimited runs.
Future<void> showGameRunsSheet(
  BuildContext context, {
  required int maxRuns,
  required int questions,
  required int refillMinutes,
  required bool unlimited,
  required int Function() runs,
  required DateTime? Function() nextRefillAt,
  VoidCallback? onBuyPremium,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => GameRunsSheet(
      maxRuns: maxRuns,
      questions: questions,
      refillMinutes: refillMinutes,
      unlimited: unlimited,
      runs: runs,
      nextRefillAt: nextRefillAt,
      onBuyPremium: onBuyPremium,
    ),
  );
}

/// The body of [showGameRunsSheet].
class GameRunsSheet extends StatefulWidget {
  final int maxRuns;
  final int questions;
  final int refillMinutes;
  final bool unlimited;
  final int Function() runs;
  final DateTime? Function() nextRefillAt;
  final VoidCallback? onBuyPremium;

  const GameRunsSheet({
    super.key,
    required this.maxRuns,
    required this.questions,
    required this.refillMinutes,
    required this.unlimited,
    required this.runs,
    required this.nextRefillAt,
    this.onBuyPremium,
  });

  @override
  State<GameRunsSheet> createState() => GameRunsSheetState();
}

class GameRunsSheetState extends State<GameRunsSheet> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!widget.unlimited) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final runs = widget.unlimited ? widget.maxRuns : widget.runs();
    final full = widget.unlimited || runs >= widget.maxRuns;
    final (
      IconData statusIcon,
      Color statusColor,
      String status,
    ) = widget.unlimited
        ? (Icons.all_inclusive_rounded, colors.gold, appL10n.gameRunsPremium)
        : full
        ? (Icons.check_circle_rounded, colors.green, appL10n.gameRunsFull)
        : (
            Icons.schedule_rounded,
            runs <= 0 ? colors.red : colors.accent,
            appL10n.gameRunsNextIn(gameFuelCountdown(widget.nextRefillAt())),
          );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              appL10n.gameRunsTitle,
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: 14),
            // One flag per run in stock.
            Row(
              children: [
                for (var i = 0; i < widget.maxRuns; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: i < runs
                            ? colors.accentSurface10
                            : colors.background,
                        borderRadius: BorderRadius.circular(
                          AppDimensions.radiusMedium,
                        ),
                      ),
                      child: Icon(
                        widget.unlimited
                            ? Icons.all_inclusive_rounded
                            : Icons.sports_score_rounded,
                        size: 28,
                        color: i < runs ? colors.accent : colors.gray,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Text(
              appL10n.gameRunsExplain(
                widget.questions,
                widget.maxRuns,
                widget.refillMinutes,
              ),
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 14,
                height: 1.4,
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(statusIcon, size: 20, color: statusColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status,
                    style: TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            if (!widget.unlimited && widget.onBuyPremium != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onBuyPremium!();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.gold,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppDimensions.radiusMedium,
                    ),
                  ),
                ),
                icon: const Icon(Icons.all_inclusive_rounded, size: 20),
                label: Text(
                  appL10n.gameRunsGetPremium,
                  style: const TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
