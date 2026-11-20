import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Экран 2 онбординга: наглядный прогресс по темам и практика без воды.
class OnboardingSmartPracticeStep extends StatefulWidget {
  const OnboardingSmartPracticeStep({super.key});

  @override
  State<OnboardingSmartPracticeStep> createState() =>
      _OnboardingSmartPracticeStepState();
}

class _OnboardingSmartPracticeStepState
    extends State<OnboardingSmartPracticeStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _started = true;
      _controller.value = 1;
    } else if (!_started) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final config = CountryConfig.current;
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final largeText = textScale > 1.3;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final topPad = (availableHeight * 0.022).clamp(10.0, 18.0);
        final headerToCardsGap = (availableHeight * 0.044).clamp(20.0, 36.0);
        final cardGap = (availableHeight * 0.022).clamp(12.0, 18.0);
        final cardVerticalPad = (availableHeight * 0.031).clamp(14.0, 24.0);
        final thumbSize = (availableHeight * 0.082).clamp(48.0, 62.0);
        final ringSize = (availableHeight * 0.074).clamp(48.0, 56.0);

        final textBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.onboardingSmartTitle,
                style: TextStyle(
                  fontSize: largeText ? 24 : 30,
                  fontWeight: FontWeight.w800,
                  height: 1.12,
                  letterSpacing: -0.5,
                  color: colors.primaryText,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.onboardingSmartSubtitle(config.topicsCount),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                height: 1.38,
                color: colors.secondaryText,
              ),
            ),
          ],
        );

        final cardsBlock = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StaggeredSlide(
              animation: _controller,
              begin: 0.0,
              end: 0.48,
              child: _TopicProgressPreviewCard(
                imageAsset: 'assets/images/games/hub_crossroads.webp',
                title: l10n.onboardingTopicCrossroads,
                subtitle: l10n.onboardingTopicScore(20, 20),
                progress: 1.0,
                progressAnimation: _controller,
                ringColor: colors.green,
                verticalPadding: cardVerticalPad,
                thumbSize: thumbSize,
                ringSize: ringSize,
              ),
            ),
            SizedBox(height: cardGap),
            _StaggeredSlide(
              animation: _controller,
              begin: 0.12,
              end: 0.64,
              child: _TopicProgressPreviewCard(
                imageAsset: 'assets/images/games/hub_regulator.webp',
                title: l10n.onboardingTopicRegulator,
                subtitle: l10n.onboardingTopicScore(17, 20),
                progress: 0.85,
                progressAnimation: _controller,
                ringColor: colors.accent,
                verticalPadding: cardVerticalPad,
                thumbSize: thumbSize,
                ringSize: ringSize,
              ),
            ),
            SizedBox(height: cardGap),
            _StaggeredSlide(
              animation: _controller,
              begin: 0.24,
              end: 0.78,
              child: _TopicProgressPreviewCard(
                imageAsset: 'assets/images/games/hub_parking.webp',
                title: l10n.onboardingTopicParking,
                subtitle: l10n.onboardingTopicScore(12, 20),
                progress: 0.60,
                progressAnimation: _controller,
                ringColor: colors.gold,
                verticalPadding: cardVerticalPad,
                thumbSize: thumbSize,
                ringSize: ringSize,
              ),
            ),
            SizedBox(height: cardGap),
            _StaggeredSlide(
              animation: _controller,
              begin: 0.36,
              end: 0.92,
              child: _TopicProgressPreviewCard(
                imageAsset: 'assets/images/games/hub_road_signs.webp',
                title: l10n.onboardingTopicSigns,
                subtitle: l10n.onboardingTopicScore(7, 20),
                progress: 0.35,
                progressAnimation: _controller,
                ringColor: colors.red,
                verticalPadding: cardVerticalPad,
                thumbSize: thumbSize,
                ringSize: ringSize,
              ),
            ),
          ],
        );

        return SingleChildScrollView(
          key: const ValueKey('onboarding-step-1-scroll'),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppDimensions.screenPadding,
                  topPad,
                  AppDimensions.screenPadding,
                  AppDimensions.spacingXL,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    textBlock,
                    SizedBox(height: headerToCardsGap),
                    Text(
                      l10n.onboardingProgressExample,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spacingS),
                    cardsBlock,
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StaggeredSlide extends StatelessWidget {
  const _StaggeredSlide({
    required this.animation,
    required this.begin,
    required this.end,
    required this.child,
  });

  final Animation<double> animation;
  final double begin;
  final double end;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final raw = ((animation.value - begin) / (end - begin)).clamp(0.0, 1.0);
        final t = Curves.easeOutCubic.transform(raw);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - t)),
            child: child,
          ),
        );
      },
    );
  }
}

class _TopicProgressPreviewCard extends StatelessWidget {
  const _TopicProgressPreviewCard({
    required this.imageAsset,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.progressAnimation,
    required this.ringColor,
    required this.verticalPadding,
    required this.thumbSize,
    required this.ringSize,
  });

  final String imageAsset;
  final String title;
  final String subtitle;
  final double progress;
  final Animation<double> progressAnimation;
  final Color ringColor;
  final double verticalPadding;
  final double thumbSize;
  final double ringSize;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final percentText = '${(progress * 100).round()}%';

    return Semantics(
      label: '$title, $subtitle, $percentText',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.divider, width: 1),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 18,
            vertical: verticalPadding,
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: thumbSize,
                  height: thumbSize,
                  color: colors.gray,
                  child: Image.asset(
                    imageAsset,
                    width: thumbSize,
                    height: thumbSize,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Icon(
                      Icons.traffic_rounded,
                      color: colors.accent,
                      size: 26,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        height: 1.22,
                        color: colors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        height: 1.25,
                        color: colors.secondaryText,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppDimensions.spacingM),
              AnimatedBuilder(
                animation: progressAnimation,
                builder: (context, _) {
                  final eased = Curves.easeOutCubic.transform(
                    progressAnimation.value,
                  );
                  return SizedBox(
                    width: ringSize,
                    height: ringSize,
                    child: CustomPaint(
                      painter: _ProgressRingPainter(
                        progress: progress * eased,
                        activeColor: ringColor,
                        trackColor: colors.gray,
                      ),
                      child: Center(
                        child: Text(
                          percentText,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colors.primaryText,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  const _ProgressRingPainter({
    required this.progress,
    required this.activeColor,
    required this.trackColor,
  });

  final double progress;
  final Color activeColor;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 4.5;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    final clamped = progress.clamp(0.0, 1.0);
    if (clamped <= 0) return;

    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * clamped,
      false,
      activePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.trackColor != trackColor;
}
