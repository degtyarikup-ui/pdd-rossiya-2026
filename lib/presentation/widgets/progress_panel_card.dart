import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Верх главного экрана: готовность к экзамену, четыре числа и серия дней —
/// в одной карточке.
///
/// Раньше это были две белые плиты одинакового веса, а внутри — четыре
/// цветные плитки. Ни один элемент не доминировал, и ответ на главный вопрос
/// («я готов сдавать?») был набран самым мелким кеглем на экране.
///
/// Здесь цвет тратится один раз — на дугу готовности. Зелёный и красный
/// остаются только на самих числах, без плашек, чтобы цвет снова означал
/// состояние, а не категорию.
class ProgressPanelCard extends StatelessWidget {
  const ProgressPanelCard({
    super.key,
    required this.stats,
    required this.streak,
  });

  final Map<String, int> stats;
  final Streak? streak;

  @override
  Widget build(BuildContext context) {
    final correct = stats['correctAnswers'] ?? 0;
    final answered = stats['answeredQuestions'] ?? 0;
    final wrong = stats['wrongQuestions'] ?? 0;
    final tickets = stats['passedTickets'] ?? 0;
    final totalQuestions = stats['totalQuestions'] ?? 0;
    final totalTickets = stats['totalTickets'] ?? 0;

    final readiness =
        totalQuestions > 0 ? (correct / totalQuestions * 100).round() : 0;
    final remaining = math.max(0, totalQuestions - correct);

    return Container(
      padding: const EdgeInsets.all(AppDimensions.spacingL),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _ReadinessGauge(percent: readiness),
              const SizedBox(width: AppDimensions.spacingL),
              Expanded(
                child: Text(
                  remaining > 0
                      ? appL10n.progressRemaining(remaining)
                      : appL10n.progressAllDone,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    letterSpacing: -0.1,
                    color: AppColors.primaryText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.spacingL),
          const Divider(height: 1, thickness: 1, color: AppColors.divider),
          const SizedBox(height: AppDimensions.spacingM),
          Row(
            children: [
              _Micro(value: '$answered', label: appL10n.progressDone),
              const _MicroDivider(),
              _Micro(
                value: '$correct',
                label: appL10n.progressCorrect,
                color: AppColors.green,
              ),
              const _MicroDivider(),
              _Micro(
                value: '$wrong',
                label: appL10n.progressWrong,
                color: AppColors.red,
              ),
              const _MicroDivider(),
              _Micro(
                value: '$tickets/$totalTickets',
                label: appL10n.progressTickets,
              ),
            ],
          ),
          if (streak != null) ...[
            const SizedBox(height: AppDimensions.spacingM),
            const Divider(height: 1, thickness: 1, color: AppColors.divider),
            const SizedBox(height: AppDimensions.spacingM),
            _StreakLine(streak: streak!),
          ],
        ],
      ),
    );
  }
}

/// Дуга готовности. Форма выбрана не случайно: это приборная шкала —
/// из мира предмета, а не абстрактное кольцо.
class _ReadinessGauge extends StatelessWidget {
  const _ReadinessGauge({required this.percent});

  final int percent;

  static const double _width = 118;
  static const double _arcHeight = 64;
  static const double _totalHeight = _arcHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _width,
      height: _totalHeight,
      child: Stack(
        children: [
          // Дуга занимает только верх; подпись живёт под её концами, иначе
          // скруглённые концы налезают на текст.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: CustomPaint(
              size: const Size(_width, _arcHeight),
              painter: _GaugePainter(percent / 100),
            ),
          ),
          // Число — внутри полукруга. FittedBox страхует «100%»: оно шире
          // «1%», а внутренний просвет дуги вверху сужается — без него
          // длинное значение легло бы на саму дугу.
          Positioned(
            // По низу: нижняя граница цифр совпадает с нижним краем дуги.
            bottom: 0,
            left: 18,
            right: 18,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text.rich(
                // Нижний выносной элемент шрифта исключён из разметки строки:
                // тогда нижняя граница блока совпадает с основанием цифр, и
                // «bottom: 0» ставит их ровно на уровень концов дуги. Иначе
                // пришлось бы угадывать размер выносного элемента константой.
                textHeightBehavior: const TextHeightBehavior(
                  applyHeightToFirstAscent: false,
                  applyHeightToLastDescent: false,
                ),
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$percent',
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        letterSpacing: -0.8,
                        color: AppColors.primaryText,
                      ),
                    ),
                    const TextSpan(
                      text: '%',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        color: AppColors.primaryText,
                      ),
                    ),
                  ],
                ),
                ),
              ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.progress);

  /// 0..1 — доля заполнения дуги.
  final double progress;

  static const double _stroke = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.width - _stroke) / 2;
    final center = Offset(size.width / 2, size.height - _stroke / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..color = AppColors.divider
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;

    // Полукруг: от «9 часов» по часовой стрелке до «3 часов».
    canvas.drawArc(rect, math.pi, math.pi, false, track);

    if (progress <= 0) return;

    final fill = Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, math.pi, math.pi * progress.clamp(0, 1), false, fill);
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.progress != progress;
}

class _Micro extends StatelessWidget {
  const _Micro({required this.value, required this.label, this.color});

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.1,
                letterSpacing: -0.3,
                color: color ?? AppColors.primaryText,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              height: 1.1,
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _MicroDivider extends StatelessWidget {
  const _MicroDivider();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 26,
        color: AppColors.divider,
      );
}

/// Серия одной строкой: слева текущая (горящий огонёк), справа рекорд
/// (погасший). Два огонька рядом читаются как «столько сейчас — столько было
/// лучше всего», без подписей и без ленты дней: лента занимала место, а
/// меняется раз в сутки.
class _StreakLine extends StatelessWidget {
  const _StreakLine({required this.streak});

  final Streak streak;

  @override
  Widget build(BuildContext context) {
    final hasStreak = streak.current > 0;

    return Row(
      children: [
        Icon(
          Icons.local_fire_department_rounded,
          size: 17,
          color: hasStreak ? AppColors.gold : AppColors.secondaryText,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            hasStreak
                ? appL10n.progressStreakDays(streak.current)
                : appL10n.streakStart,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryText,
            ),
          ),
        ),
        if (streak.longest > 0) ...[
          const SizedBox(width: AppDimensions.spacingM),
          const Icon(
            Icons.local_fire_department_rounded,
            size: 17,
            color: AppColors.secondaryText,
          ),
          const SizedBox(width: 6),
          Text(
            appL10n.progressRecord(streak.longest),
            maxLines: 1,
            // Тот же кегль и начертание, что у текущей серии: это парные
            // величины, и разное начертание читалось бы как разная важность.
            // Отличаются только цветом — рекорд приглушён.
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ],
    );
  }
}
