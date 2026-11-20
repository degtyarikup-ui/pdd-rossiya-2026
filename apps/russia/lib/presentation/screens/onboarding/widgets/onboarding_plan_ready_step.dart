import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/services/onboarding_service.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Экран 4 онбординга: дата готовности к экзамену по выбранному темпу и
/// краткие факты о базе.
class OnboardingPlanReadyStep extends StatefulWidget {
  const OnboardingPlanReadyStep({
    super.key,
    required this.category,
    required this.pace,
    this.now,
  });

  final TicketCategory category;
  final OnboardingPace pace;
  final DateTime? now;

  @override
  State<OnboardingPlanReadyStep> createState() =>
      _OnboardingPlanReadyStepState();
}

class _OnboardingPlanReadyStepState extends State<OnboardingPlanReadyStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _chartController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _started = true;
      _chartController.value = 1;
    } else if (!_started) {
      _started = true;
      _chartController.forward();
    }
  }

  @override
  void dispose() {
    _chartController.dispose();
    super.dispose();
  }

  String _formatShortDate(BuildContext context, DateTime date) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    try {
      return DateFormat.MMMd(locale).format(date);
    } catch (_) {
      final d = date.day.toString().padLeft(2, '0');
      final m = date.month.toString().padLeft(2, '0');
      return '$d.$m';
    }
  }

  String _formatHeadlineDate(BuildContext context, DateTime date) {
    final localeObj = Localizations.localeOf(context);
    final locale = localeObj.toLanguageTag();
    try {
      if (localeObj.languageCode == 'en') {
        return DateFormat.MMMd(locale).format(date);
      }
      return DateFormat.MMMMd(locale).format(date);
    } catch (_) {
      return _formatShortDate(context, date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final config = CountryConfig.current;
    final rules = config.examRules;
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final largeText = textScale > 1.3;

    final baseNow = widget.now ?? DateTime.now();
    final targetDate = DateTime(
      baseNow.year,
      baseNow.month,
      baseNow.day + widget.pace.forecastDays,
    );
    final axisDateLabel = _formatShortDate(context, targetDate);
    final headlineDateLabel = _formatHeadlineDate(context, targetDate);
    final categoryLabel = widget.category == TicketCategory.cd ? 'C/D' : 'A/B';

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final topPad = (availableHeight * 0.022).clamp(10.0, 18.0);
        final sectionGap = (availableHeight * 0.04).clamp(20.0, 32.0);
        final chartHeight = (availableHeight * 0.275).clamp(148.0, 214.0);
        final itemGap = (availableHeight * 0.018).clamp(10.0, 15.0);
        final itemVerticalPad = (availableHeight * 0.025).clamp(13.0, 19.0);

        return SingleChildScrollView(
          key: const ValueKey('onboarding-step-3-scroll'),
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
                    Semantics(
                      header: true,
                      child: Text(
                        l10n.onboardingPlanReadyTitle(headlineDateLabel),
                        style: TextStyle(
                          fontSize: largeText ? 24 : 30,
                          fontWeight: FontWeight.w800,
                          height: 1.12,
                          letterSpacing: -0.5,
                          color: colors.primaryText,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      config.hasCdCategory
                          ? l10n.onboardingPlanReadySubtitle(
                              categoryLabel,
                              widget.pace.minutesPerDay,
                            )
                          : l10n.onboardingPlanReadyPaceOnlySubtitle(
                              widget.pace.minutesPerDay,
                            ),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        height: 1.35,
                        color: colors.secondaryText,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    SizedBox(height: sectionGap),
                    _ReadinessForecastCard(
                      todayLabel: l10n.onboardingForecastToday,
                      targetDateLabel: axisDateLabel,
                      chartHeight: chartHeight,
                      animation: _chartController,
                    ),
                    SizedBox(height: sectionGap),
                    _PlanCheckItem(
                      text: l10n.onboardingPlanItemTickets(
                        config.ticketsPerCategory,
                        config.questionsPerCategory,
                      ),
                      verticalPadding: itemVerticalPad,
                    ),
                    SizedBox(height: itemGap),
                    _PlanCheckItem(
                      text: l10n.onboardingPlanItemExam(
                        config.examOfficeName,
                        rules.additionalPerMistake,
                      ),
                      verticalPadding: itemVerticalPad,
                    ),
                    SizedBox(height: itemGap),
                    _PlanCheckItem(
                      text: l10n.onboardingPlanItemOffline,
                      verticalPadding: itemVerticalPad,
                    ),
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

class _PlanCheckItem extends StatelessWidget {
  const _PlanCheckItem({required this.text, required this.verticalPadding});

  final String text;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.divider, width: 1),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: verticalPadding,
        ),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.greenLight,
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 32,
                height: 32,
                child: Icon(Icons.check_rounded, size: 19, color: colors.green),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  height: 1.32,
                  color: colors.primaryText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadinessForecastCard extends StatelessWidget {
  const _ReadinessForecastCard({
    required this.todayLabel,
    required this.targetDateLabel,
    required this.chartHeight,
    required this.animation,
  });

  final String todayLabel;
  final String targetDateLabel;
  final double chartHeight;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 19;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.divider, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: SizedBox(
                height: chartHeight,
                child: AnimatedBuilder(
                  animation: animation,
                  builder: (context, _) {
                    final progress = Curves.easeOutCubic.transform(
                      animation.value,
                    );
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _ForecastCurvePainter(
                              progress: progress,
                              startColor: colors.red,
                              midColor: colors.gold,
                              endColor: colors.green,
                              axisColor: colors.divider,
                              surfaceColor: colors.cardBackground,
                              flagDarkColor: colors.primaryText,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 32,
                          top: 8,
                          child: Opacity(
                            opacity: ((progress - 0.55) / 0.45).clamp(0.0, 1.0),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.cardBackground,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: colors.divider,
                                  width: 1,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                child: Text(
                                  '100%',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: colors.primaryText,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (largeText)
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    todayLabel,
                    style: TextStyle(fontSize: 13, color: colors.secondaryText),
                  ),
                  Text(
                    targetDateLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.primaryText,
                    ),
                  ),
                ],
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    todayLabel,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: colors.secondaryText,
                    ),
                  ),
                  Text(
                    targetDateLabel,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: colors.primaryText,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ForecastCurvePainter extends CustomPainter {
  const _ForecastCurvePainter({
    required this.progress,
    required this.startColor,
    required this.midColor,
    required this.endColor,
    required this.axisColor,
    required this.surfaceColor,
    required this.flagDarkColor,
  });

  final double progress;
  final Color startColor;
  final Color midColor;
  final Color endColor;
  final Color axisColor;
  final Color surfaceColor;
  final Color flagDarkColor;

  @override
  void paint(Canvas canvas, Size size) {
    final leftX = 12.0;
    final rightX = size.width - 16.0;
    final bottomY = size.height - 10.0;
    final topY = 24.0;

    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1.2;

    // Вертикальная стартовая ось и нижняя базовая линия.
    canvas.drawLine(Offset(leftX, topY - 4), Offset(leftX, bottomY), axisPaint);
    canvas.drawLine(Offset(leftX, bottomY), Offset(rightX, bottomY), axisPaint);

    final fullCurve = Path()
      ..moveTo(leftX, bottomY)
      ..cubicTo(
        leftX + (rightX - leftX) * 0.34,
        bottomY - 2,
        leftX + (rightX - leftX) * 0.62,
        topY + 4,
        rightX,
        topY,
      );

    final metrics = fullCurve.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final clamped = progress.clamp(0.0, 1.0);
    final drawLen = metric.length * clamped;
    final partial = metric.extractPath(0, drawLen);
    final currentEnd =
        metric.getTangentForOffset(drawLen)?.position ?? Offset(leftX, bottomY);

    if (drawLen > 1) {
      final fillPath = Path.from(partial)
        ..lineTo(currentEnd.dx, bottomY)
        ..lineTo(leftX, bottomY)
        ..close();

      final chartRect = Rect.fromLTRB(leftX, topY, rightX, bottomY);
      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            startColor.withValues(alpha: 0.08),
            midColor.withValues(alpha: 0.14),
            endColor.withValues(alpha: 0.24),
          ],
        ).createShader(chartRect);
      canvas.drawPath(fillPath, fillPaint);

      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.2
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [startColor, midColor, endColor],
        ).createShader(chartRect);
      canvas.drawPath(partial, strokePaint);
    }

    // Стартовая точка «Сегодня».
    canvas.drawCircle(
      Offset(leftX, bottomY),
      6.5,
      Paint()..color = surfaceColor,
    );
    canvas.drawCircle(Offset(leftX, bottomY), 4.5, Paint()..color = startColor);

    // Финишная точка 100% + клетчатый флажок.
    if (clamped > 0.85) {
      final endAlpha = ((clamped - 0.85) / 0.15).clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(rightX, topY),
        8.5,
        Paint()..color = surfaceColor.withValues(alpha: endAlpha),
      );
      canvas.drawCircle(
        Offset(rightX, topY),
        6.5,
        Paint()..color = endColor.withValues(alpha: endAlpha),
      );
      canvas.drawCircle(
        Offset(rightX, topY),
        2.5,
        Paint()..color = surfaceColor.withValues(alpha: endAlpha),
      );

      _paintFinishFlag(
        canvas,
        poleBottom: Offset(rightX, topY - 2),
        alpha: endAlpha,
      );
    }
  }

  void _paintFinishFlag(
    Canvas canvas, {
    required Offset poleBottom,
    required double alpha,
  }) {
    final poleTop = Offset(poleBottom.dx, poleBottom.dy - 18);
    final polePaint = Paint()
      ..color = flagDarkColor.withValues(alpha: 0.7 * alpha)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(poleBottom, poleTop, polePaint);

    const cols = 4;
    const rows = 3;
    const cell = 3.2;
    final flagLeft = poleTop.dx + 0.8;
    final flagTop = poleTop.dy;

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final isDark = (r + c).isEven;
        final rect = Rect.fromLTWH(
          flagLeft + c * cell,
          flagTop + r * cell,
          cell,
          cell,
        );
        canvas.drawRect(
          rect,
          Paint()
            ..color = (isDark ? flagDarkColor : surfaceColor).withValues(
              alpha: alpha,
            ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ForecastCurvePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.startColor != startColor ||
      oldDelegate.endColor != endColor ||
      oldDelegate.axisColor != axisColor;
}
