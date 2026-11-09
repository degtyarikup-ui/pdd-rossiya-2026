import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/celebration_screen.dart';

/// How Premium was activated.
enum PremiumCelebrationReason { purchased, granted, promoCode }

/// Full-screen congratulations when Premium becomes active, in the same frame
/// and motion as achievements and the daily streak.
class PremiumCelebrationScreen extends StatelessWidget {
  const PremiumCelebrationScreen({
    super.key,
    required this.reason,
    required this.onContinue,
    required this.onClose,
    this.expiresAt,
    this.message,
  });

  final PremiumCelebrationReason reason;

  /// Null means lifetime access.
  final DateTime? expiresAt;

  /// Optional details such as the admin's note or the number of days added.
  final String? message;
  final VoidCallback onContinue, onClose;

  static Future<void> show(
    BuildContext context, {
    required PremiumCelebrationReason reason,
    DateTime? expiresAt,
    String? message,
  }) {
    var closed = false;
    return showGeneralDialog<void>(
      context: context,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, _, _) {
        void close() {
          if (closed) return;
          closed = true;
          Navigator.of(context).pop();
        }

        return PremiumCelebrationScreen(
          reason: reason,
          expiresAt: expiresAt,
          message: message,
          onContinue: close,
          onClose: close,
        );
      },
    );
  }

  String _accessLabel() {
    final exp = expiresAt;
    if (exp == null) return appL10n.premiumCelebrationLifetime;
    return appL10n.premiumCelebrationUntil(
      DateFormat('d MMMM yyyy', appL10n.localeName).format(exp.toLocal()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final granted = reason == PremiumCelebrationReason.granted;
    final note = message?.trim();
    return CelebrationScreen(
      title: granted
          ? appL10n.premiumCelebrationGrantedTitle
          : appL10n.premiumCelebrationPurchasedTitle,
      description: note != null && note.isNotEmpty
          ? note
          : reason == PremiumCelebrationReason.purchased
          ? appL10n.premiumCelebrationPurchasedBody
          : appL10n.premiumCelebrationGrantedBody,
      label: _accessLabel(),
      heroBuilder: (size) => PremiumKeyArtwork(size: size),
      details: const _PremiumPerks(),
      actionLabel: appL10n.premiumCelebrationAction,
      background: AppColors.green,
      glowStrength: .38,
      onContinue: onContinue,
      onClose: onClose,
    );
  }
}

/// A car key with lights that fade around it.
class PremiumKeyArtwork extends StatefulWidget {
  const PremiumKeyArtwork({super.key, required this.size});
  final double size;

  @override
  State<PremiumKeyArtwork> createState() => _PremiumKeyArtworkState();
}

class _PremiumKeyArtworkState extends State<PremiumKeyArtwork>
    with SingleTickerProviderStateMixin {
  late final _twinkle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _twinkle.stop();
    } else if (!_twinkle.isAnimating) {
      _twinkle.repeat();
    }
  }

  @override
  void dispose() {
    _twinkle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: widget.size,
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            SvgPicture.asset('assets/images/premium/celebration_key.svg'),
            Positioned.fill(
              left: -36,
              right: -36,
              top: -16,
              bottom: -16,
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _SparklesPainter(
                      _twinkle,
                      reducedMotion: MediaQuery.disableAnimationsOf(context),
                    ),
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

class _SparklesPainter extends CustomPainter {
  _SparklesPainter(this.progress, {required this.reducedMotion})
    : super(repaint: progress);

  final Animation<double> progress;
  final bool reducedMotion;

  // Position, radius relative to the short side, and phase of the fade cycle.
  static const _sparkles = [
    (.16, .32, .045, .30),
    (.36, .13, .025, .56),
    (.76, .23, .052, .40),
    (.91, .48, .023, .91),
    (.21, .76, .037, .79),
    (.63, .92, .026, .23),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final (x, y, radius, phase) in _sparkles) {
      // Leave the star completely dark for part of each cycle.
      final cycle = (progress.value + phase) % 1;
      final pulse = math.sin(math.pi * (cycle / .68).clamp(0.0, 1.0));
      final intensity = reducedMotion ? .65 : pulse * pulse;
      if (intensity < .01) continue;

      final r = size.shortestSide * radius * (.72 + .28 * intensity);
      final c = Offset(size.width * x, size.height * y);
      paint.color = AppColors.white.withValues(alpha: .9 * intensity);
      final w = r * .28;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - r)
          ..quadraticBezierTo(c.dx + w * .3, c.dy - w * .3, c.dx + r, c.dy)
          ..quadraticBezierTo(c.dx + w * .3, c.dy + w * .3, c.dx, c.dy + r)
          ..quadraticBezierTo(c.dx - w * .3, c.dy + w * .3, c.dx - r, c.dy)
          ..quadraticBezierTo(c.dx - w * .3, c.dy - w * .3, c.dx, c.dy - r)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SparklesPainter oldDelegate) =>
      reducedMotion != oldDelegate.reducedMotion ||
      progress != oldDelegate.progress;
}

/// What Premium opens, in the words of the benefits screen.
class _PremiumPerks extends StatelessWidget {
  const _PremiumPerks();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final perks = [
      (
        Icons.sports_esports_rounded,
        l10n.premiumBenefitGamesTitle,
        l10n.premiumBenefitGamesDetail,
      ),
      (
        Icons.auto_awesome_rounded,
        l10n.premiumBenefitAiTitle,
        l10n.premiumBenefitAiDetail,
      ),
      (
        Icons.record_voice_over_rounded,
        l10n.premiumBenefitVoiceTitle,
        l10n.premiumBenefitVoiceDetail,
      ),
      (
        Icons.all_inclusive_rounded,
        l10n.premiumBenefitFeedTitle,
        l10n.premiumBenefitFeedDetail,
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      child: Column(
        children: [
          for (final (index, (icon, title, detail)) in perks.indexed) ...[
            if (index > 0) const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.white.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: AppColors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$title ',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: detail.replaceAll('\n', ' '),
                          style: TextStyle(
                            color: AppColors.white.withValues(alpha: .8),
                          ),
                        ),
                      ],
                    ),
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.25,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
