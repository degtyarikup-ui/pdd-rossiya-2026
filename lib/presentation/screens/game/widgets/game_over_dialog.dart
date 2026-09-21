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

class GameOverDialog extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
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
                  // The car the player drove — the same model as in the scene.
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
                    state.fuel <= 0 && !state.fuelUnlimited
                        ? appL10n.gameFuelEmptyTitle
                        : appL10n.gameOverDescription,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colors.secondaryText,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Score is the headline number of the run: all gold.
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
                        const SizedBox(height: 6),
                        if (isNewRecord)
                          _RecordBadge(color: colors.gold)
                        else
                          Text(
                            bestScore != null && bestScore! > 0
                                ? '${appL10n.gameScore} · ${appL10n.gameBestScore(bestScore!)}'
                                : appL10n.gameScore,
                            style: TextStyle(
                              fontFamily: 'Onest',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colors.secondaryText,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Violations lead the list: they are the key learning signal.
                  _StatRow(
                    icon: hasViolations
                        ? Icons.warning_amber_rounded
                        : Icons.verified_rounded,
                    color: hasViolations ? colors.red : colors.green,
                    label: appL10n.gameViolations,
                    value: hasViolations
                        ? '${state.violationCount}'
                        : appL10n.gameNoViolations,
                    valueColor: hasViolations ? colors.red : colors.green,
                    emphasized: true,
                  ),
                  const SizedBox(height: 8),
                  _StatRow(
                    icon: Icons.check_circle_rounded,
                    color: colors.accent,
                    label: appL10n.gameCorrectAnswers,
                    value: appL10n.gameAnswersOf(
                      state.totalCorrect,
                      state.totalAnswered,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _StatRow(
                    icon: Icons.route_rounded,
                    color: colors.accent,
                    label: appL10n.gameDistance,
                    value: distance,
                  ),
                  const SizedBox(height: 20),

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
                  if (state.fuel <= 0 &&
                      !state.fuelUnlimited &&
                      onBuyPremium != null) ...[
                    GameFuelEmptyPanel(
                      refillAt: fuelRefillAt,
                      onBuyPremium: onBuyPremium!,
                      compact: true,
                    ),
                    const SizedBox(height: 8),
                  ] else
                    ElevatedButton(
                      onPressed: onRestart,
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
/// bright colours with a thin light rim so they read on grass and asphalt.
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
    const palette = [
      Color(0xFFFF8A00),
      Color(0xFFFFD60A),
      Color(0xFF1F7CFF),
      Color(0xFF17D67A),
      Color(0xFFFF3B5C),
      Color(0xFFB65CFF),
      Color(0xFF22D3EE),
    ];
    return List.generate(count, (i) {
      // A wide fan straight up from the origin; the outer pieces go slower.
      final spread = (random.nextDouble() * 2 - 1);
      final angle = -math.pi / 2 + spread * 0.95;
      final speed =
          (0.55 + random.nextDouble() * 0.5) * (1 - spread.abs() * 0.3);
      return _Particle(
        origin: Offset(origin.dx + spread * 0.12, origin.dy),
        velocity: Offset(math.cos(angle) * speed, math.sin(angle) * speed),
        color: palette[random.nextInt(palette.length)],
        size: 8 + random.nextDouble() * 7,
        shape: _Shape.values[random.nextInt(_Shape.values.length)],
        spin: (random.nextDouble() - 0.5) * 6,
        phase: random.nextDouble() * math.pi * 2,
        delay: random.nextDouble() * 0.25,
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
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final p in particles) {
      final age = t - p.delay;
      if (age <= 0) continue;
      // Ballistic path with strong air drag, then a gentle fall: units are
      // canvas heights, so the shower stays on screen long enough to read.
      const k = 1.3;
      final drag = 1 - math.exp(-age * k);
      final x = p.origin.dx + p.velocity.dx * drag / k * 0.62;
      final y = p.origin.dy + p.velocity.dy * drag / k + 0.16 * age * age;
      final life = (1 - (age - (seconds - 1.1)) / 0.9).clamp(0.0, 1.0);
      if (life <= 0) continue;
      final sway = math.sin(age * 3.5 + p.phase) * 0.02;
      final center = Offset((x + sway) * size.width, y * size.height);
      if (center.dy > size.height + 20 || center.dy < -20) continue;
      fill.color = p.color.withValues(alpha: life);
      rim.color = Colors.white.withValues(alpha: 0.85 * life);
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
          canvas.drawOval(oval, rim);
        case _Shape.rect:
          final rect = Rect.fromCenter(
            center: Offset.zero,
            width: p.size * 1.3 * flip,
            height: p.size * 0.6,
          );
          canvas.drawRect(rect, fill);
          canvas.drawRect(rect, rim);
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
          canvas.drawRRect(rr, rim);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final Color? valueColor;
  final bool emphasized;

  const _StatRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.valueColor,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: emphasized
              ? color.withValues(alpha: 0.10)
              : colors.searchFieldFill,
          borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Long values (large text scale, narrow phones) shrink, never overflow.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: emphasized ? 18 : 16,
                    fontWeight: FontWeight.w800,
                    color: valueColor ?? colors.primaryText,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
