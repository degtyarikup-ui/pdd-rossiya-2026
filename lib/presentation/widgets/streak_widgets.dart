import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/weekday_labels.dart';
import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/flame_icon.dart';

/// Ступени серии: ближайшая из них — цель, которую показывают человеку.
/// Близкая цель тянет сильнее далёкой («ещё 2 дня до недели» против
/// «рекорд 100»), поэтому лестница частая в начале.
const List<int> streakMilestones = [3, 7, 14, 30, 50, 100, 200, 365];

/// Ближайшая цель выше текущей серии; null — все ступени пройдены.
int? nextStreakMilestone(int current) {
  for (final m in streakMilestones) {
    if (m > current) return m;
  }
  return null;
}

/// Предыдущая ступень (или 0): от неё отсчитывается полоса до следующей,
/// чтобы полоса не начиналась почти полной на длинной серии.
int previousStreakMilestone(int current) {
  var previous = 0;
  for (final m in streakMilestones) {
    if (m <= current) previous = m;
  }
  return previous;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Календарная неделя (Пн–Вс) с сегодняшним днём: так её читают все,
/// в отличие от «недели серии» со сдвигающимся началом.
List<DateTime> currentWeekDays(DateTime today) {
  final base = _day(today);
  final monday = base.subtract(Duration(days: base.weekday - 1));
  return List.generate(7, (i) => monday.add(Duration(days: i)));
}

/// Неделя серии: закрашенный кружок — день с занятием, сегодняшний
/// незакрытый — тёплая подложка с огоньком-обещанием, будущие — пустые.
/// Цвет — единственный носитель состояния: без обводок и теней.
class StreakWeekStrip extends StatelessWidget {
  const StreakWeekStrip({
    super.key,
    required this.streak,
    required this.today,
    this.size = 34,
    this.highlightToday = false,
  });

  final Streak streak;
  final DateTime today;
  final double size;

  /// Сегодняшний кружок появляется с «щелчком» (в поздравлении).
  final bool highlightToday;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final labels = weekdayShortLabels();
    final todayDay = _day(today);
    final days = currentWeekDays(todayDay);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final d in days)
          _DayDot(
            label: labels[d.weekday - 1],
            done: streak.isActiveOn(d),
            isToday: d == todayDay,
            future: d.isAfter(todayDay),
            size: size,
            pop: highlightToday && d == todayDay,
            colors: colors,
          ),
      ],
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({
    required this.label,
    required this.done,
    required this.isToday,
    required this.future,
    required this.size,
    required this.pop,
    required this.colors,
  });

  final String label;
  final bool done;
  final bool isToday;
  final bool future;
  final double size;
  final bool pop;
  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) {
    final Color fill = done
        ? colors.gold
        : isToday
        ? colors.goldLightSurface
        : colors.searchFieldFill;
    Widget dot = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      child: done
          ? Icon(Icons.check_rounded, size: size * 0.55, color: AppColors.white)
          : isToday
          ? FlameIcon(size: size * 0.45, color: colors.gold)
          : null,
    );
    if (pop) {
      dot = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 520),
        curve: const Interval(0.35, 1, curve: Curves.easeOutBack),
        builder: (context, t, child) =>
            Transform.scale(scale: 0.6 + 0.4 * t, child: child),
        child: dot,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            height: 1,
            fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
            color: isToday
                ? colors.primaryText
                : future
                ? colors.secondaryText.withValues(alpha: 0.6)
                : colors.secondaryText,
          ),
        ),
      ],
    );
  }
}

/// Полоса до ближайшей цели серии с подписью «Ещё 2 дня до 7».
class StreakGoalBar extends StatelessWidget {
  const StreakGoalBar({super.key, required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final goal = nextStreakMilestone(current);
    final from = previousStreakMilestone(current);
    final progress = goal == null
        ? 1.0
        : ((current - from) / (goal - from)).clamp(0.0, 1.0);
    final text = goal == null
        ? appL10n.streakGoalReached
        : appL10n.streakNextGoal(goal - current, goal);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
              ),
            ),
            if (goal != null)
              Text(
                '$current/$goal',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.secondaryText,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 8,
              color: colors.gold,
              backgroundColor: colors.searchFieldFill,
            ),
          ),
        ),
      ],
    );
  }
}

/// Блок серии в профиле: главное число, неделя и ближайшая цель.
///
/// На главной от серии осталась только статистика: серия — про привычку,
/// ей место рядом с достижениями, где человек смотрит на свой путь.
class StreakCard extends StatelessWidget {
  const StreakCard({super.key, required this.streak, this.today});

  final Streak streak;

  /// Для тестов; по умолчанию — сейчас.
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final now = today ?? DateTime.now();
    final active = streak.current > 0;
    final doneToday = streak.isActiveOn(now);
    final status = !active
        ? appL10n.streakStartHint
        : doneToday
        ? appL10n.streakToday
        : appL10n.streakTodayPending;

    return Container(
      padding: const EdgeInsets.all(AppDimensions.spacingL),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? colors.gold : colors.searchFieldFill,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: FlameIcon(
                  size: 26,
                  color: active ? AppColors.white : colors.secondaryText,
                ),
              ),
              const SizedBox(width: AppDimensions.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${streak.current} ',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                              color: colors.primaryText,
                            ),
                          ),
                          TextSpan(
                            text: appL10n.streakDaysWord(streak.current),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: colors.primaryText,
                            ),
                          ),
                        ],
                      ),
                      style: const TextStyle(height: 1.15),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      status,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: doneToday && active
                            ? colors.green
                            : colors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              if (streak.longest > 0) ...[
                const SizedBox(width: AppDimensions.spacingS),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colors.searchFieldFill,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.emoji_events_rounded,
                        size: 14,
                        color: colors.secondaryText,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        appL10n.progressRecord(streak.longest),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppDimensions.spacingL),
          StreakWeekStrip(streak: streak, today: now),
          const SizedBox(height: AppDimensions.spacingL),
          StreakGoalBar(current: streak.current),
        ],
      ),
    );
  }
}
