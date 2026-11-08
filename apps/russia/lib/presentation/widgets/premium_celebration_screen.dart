import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/celebration_screen.dart';

/// Why Premium just became active: the person paid (store, SBP, restore) or
/// it was granted from the admin panel. Both share one green screen.
enum PremiumCelebrationReason { purchased, granted }

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

  /// The admin's reason for a grant («Подарок»), shown instead of the body.
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
      heading: appL10n.premiumCelebrationHeading,
      title: granted
          ? appL10n.premiumCelebrationGrantedTitle
          : appL10n.premiumCelebrationPurchasedTitle,
      description: note != null && note.isNotEmpty
          ? note
          : granted
          ? appL10n.premiumCelebrationGrantedBody
          : appL10n.premiumCelebrationPurchasedBody,
      label: _accessLabel(),
      heroBuilder: (size) => PremiumSeal(size: size),
      details: const _PremiumPerks(),
      actionLabel: appL10n.premiumCelebrationAction,
      background: AppColors.green,
      glowStrength: .5,
      onContinue: onContinue,
      onClose: onClose,
    );
  }
}

/// White rosette with the Premium star; sparkles twinkle around it.
class PremiumSeal extends StatefulWidget {
  const PremiumSeal({super.key, required this.size});
  final double size;

  @override
  State<PremiumSeal> createState() => _PremiumSealState();
}

class _PremiumSealState extends State<PremiumSeal>
    with SingleTickerProviderStateMixin {
  late final _twinkle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _twinkle
        ..stop()
        ..value = .25;
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
    final size = widget.size;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned.fill(child: CustomPaint(painter: _SealPainter())),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: reduced ? 1 : 0, end: 1),
            duration: Duration(milliseconds: reduced ? 0 : 900),
            curve: const Interval(.3, 1, curve: Curves.elasticOut),
            builder: (context, t, child) => Transform.rotate(
              angle: (1 - t) * -.5,
              child: Transform.scale(scale: t, child: child),
            ),
            child: SizedBox.square(
              dimension: size * .4,
              child: SvgPicture.asset(
                'assets/images/premium/star.svg',
                colorFilter: const ColorFilter.mode(
                  AppColors.premiumRatingStar,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _SparklesPainter(_twinkle)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SealPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 * .92;
    const lobes = 16;
    final seal = Path();
    final step = math.pi * 2 / lobes;
    Offset at(double angle, double r) =>
        center + Offset(math.cos(angle), math.sin(angle)) * r;
    final start = -math.pi / 2 - step / 2;
    final start0 = at(start, radius * .9);
    seal.moveTo(start0.dx, start0.dy);
    for (var i = 0; i < lobes; i++) {
      final control = at(start + step * (i + .5), radius * 1.08);
      final end = at(start + step * (i + 1), radius * .9);
      seal.quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
    }
    seal.close();
    canvas.drawShadow(seal, const Color(0xFF0B5A37), 10, false);
    canvas.drawPath(seal, Paint()..color = AppColors.white);
    canvas.drawCircle(center, radius * .7, Paint()..color = AppColors.green);
    canvas.drawCircle(
      center,
      radius * .62,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, radius * .02)
        ..color = AppColors.white.withValues(alpha: .35),
    );
  }

  @override
  bool shouldRepaint(covariant _SealPainter oldDelegate) => false;
}

class _SparklesPainter extends CustomPainter {
  _SparklesPainter(this.progress) : super(repaint: progress);
  final Animation<double> progress;

  // (x, y) relative to the seal box, size relative to its side, phase.
  static const _sparkles = [
    (-.14, .16, .11, 0.0),
    (1.1, .1, .08, .35),
    (1.04, .88, .12, .6),
    (-.06, .94, .07, .82),
    (.5, -.16, .06, .18),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.white;
    for (final (x, y, s, phase) in _sparkles) {
      final wave = .5 + .5 * math.sin((progress.value + phase) * math.pi * 2);
      final r = size.width * s * (.55 + .45 * wave);
      final c = Offset(size.width * x, size.height * y);
      paint.color = AppColors.white.withValues(alpha: .55 + .45 * wave);
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
  bool shouldRepaint(covariant _SparklesPainter oldDelegate) => false;
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
