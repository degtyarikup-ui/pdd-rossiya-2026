import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/presentation/widgets/flame_icon.dart';

/// Карточка серии (стрика) на главном экране.
///
/// Шапка — крупное число и подпись «дней подряд», справа рекорд.
/// Ниже — 7-дневная лента (скользящее окно, оканчивающееся сегодня):
/// активные дни горят золотым огоньком, сегодняшний выделен рамкой.
class StreakWeekCard extends StatelessWidget {
  final Streak streak;
  const StreakWeekCard({super.key, required this.streak});

  static const List<String> _dayLabelsRu = [
    'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс',
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = streak.weekStripDays(today: today);

    final hasStreak = streak.current > 0;
    final showRecord = streak.longest > 0 && streak.longest > streak.current;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: hasStreak
                    ? RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            color: AppColors.primaryText,
                            height: 1.0,
                          ),
                          children: [
                            TextSpan(
                              text: '${streak.current} ',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                              ),
                            ),
                            TextSpan(
                              text: _daysWord(streak.current),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: AppColors.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text(
                            'Начните серию',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: AppColors.primaryText,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Ответьте на вопрос сегодня — зажжётся огонёк',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              color: AppColors.secondaryText,
                            ),
                          ),
                        ],
                      ),
              ),
              if (showRecord)
                _RecordBadge(value: streak.longest),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              final d = days[i];
              final isActive = streak.isActiveOn(d);
              final isToday = d.isAtSameMomentAs(today);
              return _StreakDayCell(
                label: _dayLabelsRu[d.weekday - 1],
                active: isActive,
                isToday: isToday,
              );
            }),
          ),
        ],
      ),
    );
  }

  /// Корректная форма слова «день» для русского склонения числительных.
  String _daysWord(int n) {
    final mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 14) return 'дней подряд';
    switch (n % 10) {
      case 1:
        return 'день подряд';
      case 2:
      case 3:
      case 4:
        return 'дня подряд';
      default:
        return 'дней подряд';
    }
  }
}

class _StreakDayCell extends StatelessWidget {
  final String label;
  final bool active;
  final bool isToday;

  const _StreakDayCell({
    required this.label,
    required this.active,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    // Активный день — сплошной оранжевый фон с белым огоньком.
    // Неактивный сегодняшний — чёрный контур. Прочие — бледный контур.
    // Толщина одинаковая у всех.
    final Color border = active
        ? AppColors.gold
        : (isToday ? AppColors.primaryText : AppColors.divider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? AppColors.gold
                : (isToday ? AppColors.white : Colors.transparent),
            shape: BoxShape.circle,
            border: Border.all(
              color: border,
              width: 1.2,
            ),
          ),
          child: FlameIcon(
            // Активный — белый на оранжевом; сегодня без тренировки — чёрный
            // (в цвет обводки); прочие пустые — светло-серый.
            color: active
                ? AppColors.white
                : (isToday ? AppColors.primaryText : AppColors.divider),
            size: 15,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
            color: isToday ? AppColors.primaryText : AppColors.secondaryText,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}

class _RecordBadge extends StatelessWidget {
  final int value;
  const _RecordBadge({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.homeStatGraySurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.emoji_events_rounded,
            size: 14,
            color: AppColors.secondaryText,
          ),
          const SizedBox(width: 4),
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryText,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}
