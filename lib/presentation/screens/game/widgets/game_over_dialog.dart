import 'dart:async';
import 'dart:math' as math;

import 'package:pdd_app/l10n/l10n.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdd_app/data/services/game_garage_service.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_garage.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/presentation/screens/game/controllers/game_controller.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_fuel_widgets.dart';

class GameOverDialog extends StatefulWidget {
  final GameState state;
  final String vehicleId;
  final String vehiclePaint;
  final GameThumbnailLoader? thumbnail;
  final Map<String, Uint8List> thumbnailCache;
  final VoidCallback onRestart;

  /// Kept for API compatibility; the dialog no longer shows an exit button
  /// because the game lives in a bottom-navigation tab.
  final VoidCallback? onExit;

  /// Opens the weekly rating sheet.
  final VoidCallback? onLeaderboard;

  /// Out of fuel: when set, the restart button gives way to the countdown and
  /// the premium pitch.
  final DateTime? fuelRefillAt;
  final VoidCallback? onBuyPremium;

  /// The best score before this run, or null when unknown.
  final int? bestScore;

  /// True when this run set a new personal best: shows the badge, fires the
  /// confetti burst and the celebration sound.
  final bool isNewRecord;

  const GameOverDialog({
    super.key,
    required this.state,
    this.vehicleId = 'hatch',
    this.vehiclePaint = 'red',
    this.thumbnail,
    this.thumbnailCache = const {},
    required this.onRestart,
    this.onExit,
    this.onLeaderboard,
    this.fuelRefillAt,
    this.onBuyPremium,
    this.bestScore,
    this.isNewRecord = false,
  });

  @override
  State<GameOverDialog> createState() => _GameOverDialogState();
}

class _GameOverDialogState extends State<GameOverDialog> {
  Timer? _timer;

  GameState get state => widget.state;
  // Stops being "empty" the moment the countdown ends: the restart button
  // comes back without leaving the dialog.
  bool get fuelEmpty =>
      state.fuel <= 0 &&
      !state.fuelUnlimited &&
      (widget.fuelRefillAt?.isAfter(DateTime.now()) ?? true);

  @override
  void initState() {
    super.initState();
    if (fuelEmpty) {
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
    final vehicleId = widget.vehicleId, vehiclePaint = widget.vehiclePaint;
    final thumbnail = widget.thumbnail, thumbnailCache = widget.thumbnailCache;
    final onLeaderboard = widget.onLeaderboard,
        onBuyPremium = widget.onBuyPremium;
    final bestScore = widget.bestScore, isNewRecord = widget.isNewRecord;
    final distance = state.distanceM >= 1000
        ? '${(state.distanceM / 1000).toStringAsFixed(1)} ${appL10n.gameKilometers}'
        : '${state.distanceM} ${appL10n.gameMeters}';
    final hasViolations = state.violationCount > 0;

    return Dialog(
      backgroundColor: colors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusExtraLarge),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (fuelEmpty)
                    _FuelEmptyHeader(refillAt: widget.fuelRefillAt)
                  else ...[
                    Semantics(
                      label: appL10n.gameYourCar,
                      image: true,
                      child: SizedBox(
                        height: 118,
                        child: GameCarThumbnail(
                          car: GameCar(vehicleId, vehiclePaint),
                          loader: thumbnail,
                          cache: thumbnailCache,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      appL10n.gameOver,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: colors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      appL10n.gameOverDescription,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: colors.secondaryText,
                        height: 1.35,
                      ),
                    ),
                  ],
                  SizedBox(height: fuelEmpty ? 14 : 18),

                  if (fuelEmpty)
                    _FuelScoreCard(
                      score: state.score,
                      bestScore: bestScore,
                      isNewRecord: isNewRecord,
                    )
                  else
                    Semantics(
                      label: '${appL10n.gameScore}: ${state.score}',
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.star_rounded,
                                size: 40,
                                color: colors.gold,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '${state.score}',
                                    style: TextStyle(
                                      fontFamily: 'Onest',
                                      fontSize: 44,
                                      fontWeight: FontWeight.w800,
                                      height: 1,
                                      color: colors.gold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (isNewRecord) ...[
                            const SizedBox(height: 6),
                            _RecordBadge(color: colors.gold),
                          ] else if (bestScore != null && bestScore > 0) ...[
                            const SizedBox(height: 6),
                            Text(
                              appL10n.gameBestScore(bestScore),
                              style: TextStyle(
                                fontFamily: 'Onest',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.secondaryText,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  SizedBox(height: fuelEmpty ? 12 : 18),

                  if (fuelEmpty)
                    _FuelStatsStrip(
                      violations: state.violationCount,
                      correct: state.totalCorrect,
                      distance: distance,
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: _StatTile(
                            icon: hasViolations
                                ? Icons.warning_amber_rounded
                                : Icons.verified_rounded,
                            color: hasViolations ? colors.red : colors.green,
                            label: appL10n.gameViolations,
                            value: '${state.violationCount}',
                            emphasized: hasViolations,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatTile(
                            icon: Icons.check_circle_rounded,
                            color: colors.accent,
                            label: appL10n.gameCorrectAnswers,
                            value: '${state.totalCorrect}',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatTile(
                            icon: Icons.route_rounded,
                            color: colors.accent,
                            label: appL10n.gameDistance,
                            value: distance,
                          ),
                        ),
                      ],
                    ),
                  SizedBox(height: fuelEmpty ? 14 : 18),

                  if (onLeaderboard != null) ...[
                    OutlinedButton.icon(
                      onPressed: onLeaderboard,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.accent,
                        side: BorderSide(
                          color: colors.accent.withValues(alpha: 0.35),
                        ),
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppDimensions.radiusMedium,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.emoji_events_rounded, size: 20),
                      label: Text(
                        appL10n.gameWeeklyRating,
                        style: const TextStyle(
                          fontFamily: 'Onest',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (fuelEmpty && onBuyPremium != null) ...[
                    GameFuelPremiumPitch(onBuyPremium: onBuyPremium),
                    const SizedBox(height: 8),
                  ] else
                    ElevatedButton(
                      onPressed: widget.onRestart,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppDimensions.radiusMedium,
                          ),
                        ),
                      ),
                      child: Text(
                        appL10n.gameRestart,
                        style: const TextStyle(
                          fontFamily: 'Onest',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (isNewRecord)
            const Positioned.fill(child: IgnorePointer(child: ConfettiBurst())),
        ],
      ),
    );
  }
}

class _FuelEmptyHeader extends StatelessWidget {
  final DateTime? refillAt;

  const _FuelEmptyHeader({required this.refillAt});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      children: [
        const GameFuelEmptyIcon(size: 58),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appL10n.gameFuelEmptyTitle,
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                appL10n.gameFuelRefillIn(gameFuelCountdown(refillAt)),
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 13,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                  color: colors.red,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FuelScoreCard extends StatelessWidget {
  final int score;
  final int? bestScore;
  final bool isNewRecord;

  const _FuelScoreCard({
    required this.score,
    required this.bestScore,
    required this.isNewRecord,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      label: '${appL10n.gameScore}: $score',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.gold.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.gold.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.star_rounded, size: 28, color: colors.gold),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '$score',
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: colors.gold,
                  ),
                ),
              ),
            ),
            if (isNewRecord) ...[
              const SizedBox(width: 8),
              Flexible(child: _RecordBadge(color: colors.gold)),
            ] else if (bestScore != null && bestScore! > 0) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  appL10n.gameBestScore(bestScore!),
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
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

class _FuelStatsStrip extends StatelessWidget {
  final int violations;
  final int correct;
  final String distance;

  const _FuelStatsStrip({
    required this.violations,
    required this.correct,
    required this.distance,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final hasViolations = violations > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
      decoration: BoxDecoration(
        color: colors.searchFieldFill,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
      ),
      child: Row(
        children: [
          Expanded(
            child: _CompactStat(
              icon: hasViolations
                  ? Icons.warning_amber_rounded
                  : Icons.verified_rounded,
              color: hasViolations ? colors.red : colors.green,
              label: appL10n.gameViolations,
              value: '$violations',
            ),
          ),
          _StatDivider(color: colors.gray.withValues(alpha: 0.30)),
          Expanded(
            child: _CompactStat(
              icon: Icons.check_circle_rounded,
              color: colors.accent,
              label: appL10n.gameCorrectAnswers,
              value: '$correct',
            ),
          ),
          _StatDivider(color: colors.gray.withValues(alpha: 0.30)),
          Expanded(
            child: _CompactStat(
              icon: Icons.route_rounded,
              color: colors.accent,
              label: appL10n.gameDistance,
              value: distance,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  final Color color;
  const _StatDivider({required this.color});

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 38, color: color);
}

class _CompactStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _CompactStat({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: colors.primaryText,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Onest',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: colors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordBadge extends StatefulWidget {
  final Color color;
  const _RecordBadge({required this.color});

  @override
  State<_RecordBadge> createState() => _RecordBadgeState();
}

class _RecordBadgeState extends State<_RecordBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Pops in with an overshoot, then rests.
    final scale = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );
    return ScaleTransition(
      scale: scale,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events_rounded, size: 16, color: widget.color),
            const SizedBox(width: 5),
            Text(
              appL10n.gameNewRecord,
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: widget.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A one-shot burst of confetti and stars flying out from the score, with
/// gravity, drag, tumbling and fade — no packages, one CustomPainter.
/// A slow, readable shower of confetti: flat rectangles, discs and pills in
/// three brand colours; they burst out from the score and drift down.
/// [origin] is where the pieces come from (fractions of the canvas); the
/// default is the middle of the screen, the game uses the top edge of the
/// question card.
class ConfettiBurst extends StatefulWidget {
  final Duration duration;
  final Offset origin;
  final int count;
  const ConfettiBurst({
    super.key,
    this.duration = const Duration(milliseconds: 2800),
    this.origin = const Offset(0.5, 0.34),
    this.count = 70,
  });

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..forward();
  late final List<_Particle> _particles = _spawn(widget.origin, widget.count);

  static List<_Particle> _spawn(Offset origin, int count) {
    final random = math.Random();
    // Three brand colours only: accent blue, gold and green.
    const palette = [Color(0xFF0574F8), Color(0xFFFFB21C), Color(0xFF2BC280)];
    return List.generate(count, (i) {
      // A burst in every direction (a little stronger upwards) that then
      // drifts down: it flies out instead of just falling.
      final angle = random.nextDouble() * math.pi * 2;
      final lift = math.sin(angle) < 0 ? 1.25 : 0.8;
      final speed = (1.1 + random.nextDouble() * 1.3) * lift;
      return _Particle(
        origin: origin,
        velocity: Offset(math.cos(angle) * speed, math.sin(angle) * speed),
        color: palette[random.nextInt(palette.length)],
        size: 8 + random.nextDouble() * 7,
        shape: _Shape.values[random.nextInt(_Shape.values.length)],
        spin: (random.nextDouble() - 0.5) * 8,
        phase: random.nextDouble() * math.pi * 2,
        delay: random.nextDouble() * 0.08,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        painter: _ConfettiPainter(
          _particles,
          _controller.value,
          widget.duration.inMilliseconds / 1000,
        ),
        size: Size.infinite,
      ),
    );
  }
}

enum _Shape { rect, disc, pill }

class _Particle {
  final Offset origin; // fraction of the canvas
  final Offset velocity; // canvas heights per second
  final Color color;
  final double size;
  final _Shape shape;
  final double spin;
  final double phase;
  final double delay;

  const _Particle({
    required this.origin,
    required this.velocity,
    required this.color,
    required this.size,
    required this.shape,
    required this.spin,
    required this.phase,
    required this.delay,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress; // 0..1 over the whole burst
  final double seconds;

  const _ConfettiPainter(this.particles, this.progress, this.seconds);

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress * seconds;
    final fill = Paint();
    for (final p in particles) {
      final age = t - p.delay;
      if (age <= 0) continue;
      // Ballistic path with strong air drag, then a gentle fall: units are
      // canvas heights, so the shower stays on screen long enough to read.
      const k = 2.6;
      final drag = 1 - math.exp(-age * k);
      final x = p.origin.dx + p.velocity.dx * drag / k * 0.62;
      final y = p.origin.dy + p.velocity.dy * drag / k + 0.09 * age * age;
      final life = (1 - (age - (seconds - 1.1)) / 0.9).clamp(0.0, 1.0);
      if (life <= 0) continue;
      final sway = math.sin(age * 3.5 + p.phase) * 0.02;
      final center = Offset((x + sway) * size.width, y * size.height);
      if (center.dy > size.height + 20 || center.dy < -20) continue;
      fill.color = p.color.withValues(alpha: life);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(p.phase + age * p.spin);
      // The apparent width breathes as the piece tumbles.
      final flip = math.cos(age * 4 + p.phase).abs() * 0.65 + 0.35;
      switch (p.shape) {
        case _Shape.disc:
          final oval = Rect.fromCenter(
            center: Offset.zero,
            width: p.size * flip,
            height: p.size,
          );
          canvas.drawOval(oval, fill);
        case _Shape.rect:
          final rect = Rect.fromCenter(
            center: Offset.zero,
            width: p.size * 1.3 * flip,
            height: p.size * 0.6,
          );
          canvas.drawRect(rect, fill);
        case _Shape.pill:
          final rr = RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size * 1.5 * flip,
              height: p.size * 0.5,
            ),
            Radius.circular(p.size),
          );
          canvas.drawRRect(rr, fill);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final bool emphasized;

  const _StatTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: emphasized
              ? color.withValues(alpha: 0.10)
              : colors.searchFieldFill,
          borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: emphasized ? color : colors.primaryText,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Onest',
                fontSize: 11,
                height: 1.15,
                fontWeight: FontWeight.w600,
                color: colors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
