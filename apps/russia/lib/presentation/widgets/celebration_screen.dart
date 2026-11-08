import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// The shared full-screen frame for daily activity, achievement and Premium
/// celebrations.
class CelebrationScreen extends StatefulWidget {
  const CelebrationScreen({
    super.key,
    required this.heading,
    required this.title,
    required this.description,
    required this.label,
    required this.heroBuilder,
    required this.onContinue,
    required this.onClose,
    this.titleWidget,
    this.position = 1,
    this.total = 1,
    this.isStreak = false,
    this.background,
    this.glowStrength,
    this.details,
    this.actionLabel,
  });
  final String heading, title, description, label;
  final Widget Function(double size) heroBuilder;
  final Widget? titleWidget;
  final VoidCallback onContinue, onClose;
  final int position, total;
  final bool isStreak;

  /// Overrides the accent (achievement) or gold (streak) backdrop.
  final Color? background;

  /// Strength of the white halo behind the hero; a white hero needs less.
  final double? glowStrength;

  /// Extra content under the label, e.g. what Premium unlocks.
  final Widget? details;

  /// Replaces «Продолжить» on the main button.
  final String? actionLabel;
  @override
  State<CelebrationScreen> createState() => _CelebrationScreenState();
}

class _CelebrationScreenState extends State<CelebrationScreen>
    with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  );
  final _backdropKey = GlobalKey();
  final _badgeKey = GlobalKey();
  final _scrollController = ScrollController();
  Offset? _glowCenter;
  double _glowBadgeSize = 160;
  bool _positionScheduled = false;

  @override
  void initState() {
    super.initState();
    HapticFeedbackHelper.success();
    unawaited(
      SoundEffectsService.instance.playCelebration(streak: widget.isStreak),
    );
    _scrollController.addListener(_syncGlowPosition);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _spin.stop();
    } else if (!_spin.isAnimating) {
      _spin.repeat();
    }
  }

  void _syncGlowPosition() {
    if (_positionScheduled) return;
    _positionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _positionScheduled = false;
      if (!mounted) return;
      final badge = _badgeKey.currentContext?.findRenderObject();
      final backdrop = _backdropKey.currentContext?.findRenderObject();
      if (badge is! RenderBox || backdrop is! RenderBox) return;
      final center = badge.localToGlobal(
        badge.size.center(Offset.zero),
        ancestor: backdrop,
      );
      if (_glowCenter == center && _glowBadgeSize == badge.size.width) return;
      setState(() {
        _glowCenter = center;
        _glowBadgeSize = badge.size.width;
      });
    });
  }

  @override
  void dispose() {
    _spin.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final background =
        widget.background ??
        (widget.isStreak ? AppColors.gold : AppColors.accent);
    _syncGlowPosition();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: background,
      ),
      child: Scaffold(
        backgroundColor: background,
        body: Stack(
          key: _backdropKey,
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: CustomPaint(
                painter: _AwardGlow(
                  center: _glowCenter,
                  badgeSize: _glowBadgeSize,
                  rotation: _spin,
                  glowStrength:
                      widget.glowStrength ?? (widget.isStreak ? .32 : 1),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.all(AppDimensions.screenPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const SizedBox(width: 48),
                            Expanded(
                              child: Text(
                                widget.heading,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.white,
                                ),
                              ),
                            ),
                            IconButton.filled(
                              tooltip: appL10n.close,
                              style: IconButton.styleFrom(
                                backgroundColor: AppColors.white,
                                foregroundColor: AppColors.primaryText,
                                minimumSize: const Size(48, 48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppDimensions.buttonRadius,
                                  ),
                                ),
                              ),
                              onPressed: widget.onClose,
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final badgeSize = math.min(
                                160.0,
                                math.max(128.0, constraints.maxHeight * .28),
                              );
                              return SingleChildScrollView(
                                controller: _scrollController,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: constraints.maxHeight,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      TweenAnimationBuilder<double>(
                                        tween: Tween(
                                          begin: reduced ? 1 : .82,
                                          end: 1,
                                        ),
                                        duration: Duration(
                                          milliseconds: reduced ? 0 : 650,
                                        ),
                                        curve: Curves.easeOutBack,
                                        builder: (context, scale, child) =>
                                            Transform.scale(
                                              scale: scale,
                                              child: child,
                                            ),
                                        child: SizedBox(
                                          key: _badgeKey,
                                          width: badgeSize,
                                          height: badgeSize,
                                          child: widget.heroBuilder(badgeSize),
                                        ),
                                      ),
                                      const SizedBox(height: 32),
                                      Semantics(
                                        liveRegion: true,
                                        child:
                                            widget.titleWidget ??
                                            Text(
                                              widget.title,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                fontSize: 30,
                                                fontWeight: FontWeight.w800,
                                                color: AppColors.white,
                                                height: 1.15,
                                              ),
                                            ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        widget.description,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 16,
                                          height: 1.45,
                                          color: AppColors.white.withValues(
                                            alpha: .8,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 7,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.white.withValues(
                                            alpha: .16,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            40,
                                          ),
                                        ),
                                        child: Text(
                                          widget.label,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.white,
                                          ),
                                        ),
                                      ),
                                      if (widget.details != null) ...[
                                        const SizedBox(height: 24),
                                        widget.details!,
                                      ],
                                      const SizedBox(height: 24),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        if (widget.total > 1) ...[
                          Text(
                            appL10n.achievementAwardPosition(
                              widget.position,
                              widget.total,
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.white,
                            foregroundColor: widget.isStreak
                                ? AppColors.primaryText
                                : background,
                            minimumSize: const Size.fromHeight(56),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppDimensions.buttonRadius,
                              ),
                            ),
                            textStyle: const TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: widget.onContinue,
                          child: Text(
                            widget.actionLabel ?? appL10n.continueButton,
                          ),
                        ),
                      ],
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

class _AwardGlow extends CustomPainter {
  _AwardGlow({
    required this.center,
    required this.badgeSize,
    required this.rotation,
    required this.glowStrength,
  }) : super(repaint: rotation);

  final Animation<double> rotation;
  final Offset? center;
  final double badgeSize;
  final double glowStrength;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = center ?? Offset(size.width / 2, size.height * .4);
    final rayRadius = badgeSize * 2.45;
    final rayPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
      ..shader = RadialGradient(
        colors: [
          AppColors.white.withValues(alpha: 0),
          AppColors.white.withValues(alpha: .18),
          AppColors.white.withValues(alpha: .12),
          AppColors.white.withValues(alpha: .035),
          AppColors.white.withValues(alpha: 0),
        ],
        stops: const [0, .18, .4, .72, 1],
      ).createShader(Rect.fromCircle(center: origin, radius: rayRadius));
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6 - math.pi / 2 + rotation.value * math.pi * 2;
      final path = Path()
        ..moveTo(origin.dx, origin.dy)
        ..lineTo(
          origin.dx + math.cos(a - .095) * rayRadius,
          origin.dy + math.sin(a - .095) * rayRadius,
        )
        ..lineTo(
          origin.dx + math.cos(a + .095) * rayRadius,
          origin.dy + math.sin(a + .095) * rayRadius,
        )
        ..close();
      canvas.drawPath(path, rayPaint);
    }
    final glowRadius = badgeSize * 1.55;
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(1, 1 / 1.4);
    canvas.drawCircle(
      Offset.zero,
      glowRadius,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                AppColors.white.withValues(alpha: .92 * glowStrength),
                AppColors.white.withValues(alpha: .84 * glowStrength),
                AppColors.white.withValues(alpha: .46 * glowStrength),
                AppColors.white.withValues(alpha: .1 * glowStrength),
                AppColors.white.withValues(alpha: 0),
              ],
              stops: const [0, .18, .42, .7, 1],
            ).createShader(
              Rect.fromCircle(center: Offset.zero, radius: glowRadius),
            ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AwardGlow oldDelegate) =>
      center != oldDelegate.center ||
      badgeSize != oldDelegate.badgeSize ||
      glowStrength != oldDelegate.glowStrength;
}
