import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/core/utils/weekday_labels.dart';
import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';
import 'package:pdd_app/presentation/widgets/flame_icon.dart';
import 'package:pdd_app/presentation/widgets/streak_widgets.dart';

/// Открывает модальный лист с календарём серии: дни с занятиями отмечены
/// огоньком, можно листать месяцы назад до самого раннего сохранённого дня.
Future<void> showStreakCalendarSheet(
  BuildContext context, {
  required Streak streak,
  DateTime? today,
}) {
  final colors = AppColors.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: colors.cardBackground,
    constraints: const BoxConstraints(maxWidth: 600),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => StreakCalendarSheet(streak: streak, today: today),
  );
}

class StreakCalendarSheet extends StatefulWidget {
  const StreakCalendarSheet({super.key, required this.streak, this.today});

  final Streak streak;

  /// Для тестов; по умолчанию — сейчас.
  final DateTime? today;

  @override
  State<StreakCalendarSheet> createState() => _StreakCalendarSheetState();
}

class _StreakCalendarSheetState extends State<StreakCalendarSheet> {
  late final DateTime _today = Streak.day(widget.today ?? DateTime.now());
  late final DateTime _currentMonth = DateTime(_today.year, _today.month);
  late final DateTime _minMonth = _computeMinMonth();
  late DateTime _displayedMonth = _currentMonth;

  @override
  void initState() {
    super.initState();
    final locale = appL10n.localeName;
    if (!DateFormat.localeExists(locale)) {
      initializeDateFormatting(locale).then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  DateTime _computeMinMonth() {
    var minMonth = DateTime(_currentMonth.year, _currentMonth.month - 11);
    for (final d in widget.streak.activeDays) {
      final m = DateTime(d.year, d.month);
      if (m.isBefore(minMonth)) minMonth = m;
    }
    final start = widget.streak.startDate;
    if (start != null) {
      final m = DateTime(start.year, start.month);
      if (m.isBefore(minMonth)) minMonth = m;
    }
    final last = widget.streak.lastActiveDate;
    if (widget.streak.current > 0 && last != null) {
      final runStart = Streak.shiftDay(last, 1 - widget.streak.current);
      final m = DateTime(runStart.year, runStart.month);
      if (m.isBefore(minMonth)) minMonth = m;
    }
    return minMonth;
  }

  bool get _canGoPrev => _displayedMonth.isAfter(_minMonth);
  bool get _canGoNext => _displayedMonth.isBefore(_currentMonth);

  void _shiftMonth(int delta) {
    final target = DateTime(
      _displayedMonth.year,
      _displayedMonth.month + delta,
    );
    if (target.isBefore(_minMonth) || target.isAfter(_currentMonth)) return;
    HapticFeedbackHelper.select();
    setState(() => _displayedMonth = target);
  }

  String _formatMonthTitle(DateTime month) {
    final locale = appL10n.localeName;
    if (DateFormat.localeExists(locale)) {
      final raw = DateFormat('LLLL yyyy', locale).format(month);
      if (raw.isEmpty) return raw;
      return raw[0].toUpperCase() + raw.substring(1);
    }
    return DateFormat('MM.yyyy').format(month);
  }

  int _activeDaysInMonth(DateTime month) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    var count = 0;
    for (var day = 1; day <= daysInMonth; day++) {
      if (widget.streak.hasActivityOn(DateTime(month.year, month.month, day))) {
        count++;
      }
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final streak = widget.streak;
    final active = streak.current > 0;
    final doneToday = streak.hasActivityOn(_today);
    final status = !active
        ? appL10n.streakStartHint
        : doneToday
        ? appL10n.streakToday
        : appL10n.streakTodayPending;
    final monthActiveCount = _activeDaysInMonth(_displayedMonth);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppDimensions.screenPadding,
          0,
          AppDimensions.screenPadding,
          AppDimensions.spacingXL,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                StreakFlameBadge(active: active, size: 52),
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
              ],
            ),
            if (streak.longest > 0) ...[
              const SizedBox(height: AppDimensions.spacingM),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.spacingM,
                  vertical: AppDimensions.spacingS,
                ),
                decoration: BoxDecoration(
                  color: colors.goldLightSurface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        appL10n.personalRecord,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.primaryText,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppDimensions.spacingS),
                    Text(
                      appL10n.progressStreakDays(streak.longest),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.gold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppDimensions.spacingL),
            StreakGoalBar(current: streak.current),
            const SizedBox(height: AppDimensions.spacingL),
            Divider(height: 1, color: colors.divider),
            const SizedBox(height: AppDimensions.spacingL),
            Row(
              children: [
                Semantics(
                  label: appL10n.streakCalendarPrevMonth,
                  button: true,
                  enabled: _canGoPrev,
                  child: AppChromeIconButton(
                    key: const ValueKey('streak_calendar_prev_month'),
                    icon: Icons.chevron_left_rounded,
                    backgroundColor: colors.searchFieldFill,
                    iconColor: _canGoPrev
                        ? colors.primaryText
                        : colors.secondaryText.withValues(alpha: 0.4),
                    onTap: _canGoPrev ? () => _shiftMonth(-1) : null,
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        _formatMonthTitle(_displayedMonth),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: colors.primaryText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        appL10n.streakCalendarMonthActiveDays(monthActiveCount),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: monthActiveCount > 0
                              ? colors.gold
                              : colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                Semantics(
                  label: appL10n.streakCalendarNextMonth,
                  button: true,
                  enabled: _canGoNext,
                  child: AppChromeIconButton(
                    key: const ValueKey('streak_calendar_next_month'),
                    icon: Icons.chevron_right_rounded,
                    backgroundColor: colors.searchFieldFill,
                    iconColor: _canGoNext
                        ? colors.primaryText
                        : colors.secondaryText.withValues(alpha: 0.4),
                    onTap: _canGoNext ? () => _shiftMonth(1) : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingM),
            _MonthGrid(
              month: _displayedMonth,
              today: _today,
              streak: streak,
              colors: colors,
            ),
            const SizedBox(height: AppDimensions.spacingS),
            Wrap(
              spacing: AppDimensions.spacingL,
              runSpacing: AppDimensions.spacingS,
              alignment: WrapAlignment.center,
              children: [
                _LegendItem(
                  icon: Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: streakHeatGradient,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const FlameIcon(size: 11, color: AppColors.white),
                  ),
                  label: appL10n.streakCalendarStudied,
                  colors: colors,
                ),
                if (_displayedMonth == _currentMonth && !doneToday)
                  _LegendItem(
                    icon: Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.goldLightSurface,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${_today.day}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          height: 1,
                          color: colors.gold,
                        ),
                      ),
                    ),
                    label: appL10n.streakCalendarToday,
                    colors: colors,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.today,
    required this.streak,
    required this.colors,
  });

  final DateTime month;
  final DateTime today;
  final Streak streak;
  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) {
    final labels = weekdayShortLabels();
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final leadingEmpty = firstOfMonth.weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final totalCells = leadingEmpty + daysInMonth;
    final rowCount = (totalCells / 7).ceil();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.secondaryText,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppDimensions.spacingS),
        for (var row = 0; row < rowCount; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                for (var col = 0; col < 7; col++) ...[
                  if (col > 0) const SizedBox(width: 4),
                  Expanded(
                    child: _buildCell(
                      row * 7 + col - leadingEmpty + 1,
                      daysInMonth,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCell(int dayNum, int daysInMonth) {
    if (dayNum < 1 || dayNum > daysInMonth) {
      return const SizedBox(height: 46);
    }
    final date = DateTime(month.year, month.month, dayNum);
    final done = streak.hasActivityOn(date);
    final isToday = date == today;
    final isFuture = date.isAfter(today);
    final iso =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    return _CalendarDayCell(
      key: ValueKey('streak_calendar_day_$iso'),
      day: dayNum,
      done: done,
      isToday: isToday,
      isFuture: isFuture,
      colors: colors,
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    super.key,
    required this.day,
    required this.done,
    required this.isToday,
    required this.isFuture,
    required this.colors,
  });

  final int day;
  final bool done;
  final bool isToday;
  final bool isFuture;
  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) {
    final semanticParts = <String>[
      '$day',
      if (isToday) appL10n.streakCalendarToday,
      if (done) appL10n.streakCalendarStudied,
    ];

    final BoxDecoration decoration;
    final Widget content;

    if (done) {
      decoration = BoxDecoration(
        gradient: streakHeatGradient,
        borderRadius: BorderRadius.circular(12),
      );
      content = Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const FlameIcon(size: 16, color: AppColors.white),
          const SizedBox(height: 2),
          Text(
            '$day',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              height: 1,
              color: AppColors.white,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
    } else if (isToday) {
      decoration = BoxDecoration(
        color: colors.goldLightSurface,
        borderRadius: BorderRadius.circular(12),
      );
      content = Text(
        '$day',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          height: 1.1,
          color: colors.gold,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    } else {
      decoration = BoxDecoration(
        color: isFuture ? Colors.transparent : colors.searchFieldFill,
        borderRadius: BorderRadius.circular(12),
      );
      content = Text(
        '$day',
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          height: 1.1,
          color: isFuture
              ? colors.secondaryText.withValues(alpha: 0.5)
              : colors.primaryText.withValues(alpha: 0.72),
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    }

    return Semantics(
      label: semanticParts.join(', '),
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 46),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          alignment: Alignment.center,
          decoration: decoration,
          child: content,
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.icon,
    required this.label,
    required this.colors,
  });

  final Widget icon;
  final String label;
  final AppThemeColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.secondaryText,
            ),
          ),
        ),
      ],
    );
  }
}
