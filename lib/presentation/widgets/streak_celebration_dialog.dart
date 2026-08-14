import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/flame_icon.dart';
import 'package:pdd_app/core/utils/weekday_labels.dart';

/// Поздравление за зажжённый сегодня огонёк.
///
/// Показывается один раз в день, когда пользователь впервые после полуночи
/// ответил на вопрос. Открывается из главного экрана при возврате
/// с тренировки (см. home_screen.dart → _maybeShowStreakCelebration).
Future<void> showStreakCelebrationDialog({
  required BuildContext context,
  required Streak streak,
}) async {
  HapticFeedbackHelper.success();
  await showGeneralDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    barrierDismissible: true,
    barrierLabel: appL10n.streakBarrierLabel,
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (ctx, _, _) => _StreakCelebrationDialog(streak: streak),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _StreakCelebrationDialog extends StatefulWidget {
  final Streak streak;
  const _StreakCelebrationDialog({required this.streak});

  @override
  State<_StreakCelebrationDialog> createState() =>
      _StreakCelebrationDialogState();
}

class _StreakCelebrationDialogState extends State<_StreakCelebrationDialog> {
  @override
  Widget build(BuildContext context) {
    final s = widget.streak;
    // «Личный рекорд» — только если уже была серия выше единицы. На первый
    // день current=1==longest, но это не повод хвалить за «рекорд».
    final isNewRecord = s.current > 1 && s.current >= s.longest;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = s.weekStripDays(today: today);

    return Dialog(
      backgroundColor: AppColors.cardBackground,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _StreakFlameBurst(),
            const SizedBox(height: AppDimensions.spacingL),
            Text(
              '${s.current}',
              style: const TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.6,
                height: 1.0,
                color: AppColors.primaryText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              appL10n.streakDaysWord(s.current),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryText,
                height: 1.2,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingM),
            if (isNewRecord) ...[
              _RecordChip(),
              const SizedBox(height: AppDimensions.spacingM),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                _motivationText(s.current, isNewRecord: isNewRecord),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: AppColors.secondaryText,
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.spacingXL),
            _WeekStrip(
              days: days,
              today: today,
              isActive: s.isActiveOn,
              labels: weekdayShortLabels(),
            ),
            const SizedBox(height: AppDimensions.spacingXL),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppDimensions.buttonRadius),
                  ),
                  elevation: 0,
                ),
                onPressed: () {
                  HapticFeedbackHelper.tap();
                  Navigator.of(context).pop();
                },
                child: Text(
                  appL10n.continueButton,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _motivationText(int n, {required bool isNewRecord}) {
    if (isNewRecord && n > 1) return appL10n.streakMotivationRecord;
    if (n == 1) return appL10n.streakMotivationFirst;
    if (n < 7) return appL10n.streakMotivationWeek;
    if (n < 30) return appL10n.streakMotivationHabit;
    return appL10n.streakMotivationMonth;
  }
}

/// Эпичное появление огонька: вспышка-бурст → лучи-солнце наезжают и медленно
/// вращаются → пламя выскакивает с пружинистым overshoot → взлетают искры →
/// далее непрерывное мерцание и покачивание. Всё в фирменном золотом стиле.
class _StreakFlameBurst extends StatefulWidget {
  const _StreakFlameBurst();

  @override
  State<_StreakFlameBurst> createState() => _StreakFlameBurstState();
}

class _StreakFlameBurstState extends State<_StreakFlameBurst>
    with TickerProviderStateMixin {
  // Появление (проигрывается один раз), «живое горение» (цикл) и медленное
  // вращение лучей (отдельный длинный цикл, чтобы не было рывка).
  late final AnimationController _entrance;
  late final AnimationController _ambient;
  late final AnimationController _spin;

  static const double _area = 150;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 9000),
    )..repeat();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _ambient.dispose();
    _spin.dispose();
    super.dispose();
  }

  double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _area,
      height: _area,
      child: AnimatedBuilder(
        animation: Listenable.merge([_entrance, _ambient, _spin]),
        builder: (context, _) {
          final e = _entrance.value; // появление 0..1
          final a = _ambient.value; // цикл горения 0..1
          final angle = a * 2 * math.pi;

          // Подпрогрессы появления.
          final flamePop = Curves.easeOutBack.transform(_clamp01(e / 0.9));
          final flameOpacity = _clamp01(e * 5);
          final raysGrow = Curves.easeOutBack.transform(_clamp01(e / 0.8));
          final raysOpacity = _clamp01(e / 0.6);
          final flashT = _clamp01(e / 0.4); // вспышка в первые 40%

          // Живое мерцание: сумма синусоид с целыми частотами — бесшовный цикл.
          final flicker = math.sin(angle) * 0.55 +
              math.sin(angle * 3 + 1.3) * 0.3 +
              math.sin(angle * 2 + 0.6) * 0.15; // ≈ -1..1
          final f = (flicker + 1) / 2; // 0..1
          final scaleY = 1.0 + f * 0.14;
          final scaleX = 1.0 - f * 0.05;
          final sway = math.sin(angle * 2) * 0.038; // ±~2.2°
          final coreOpacity = _clamp01(0.28 + f * 0.5);

          Widget flame(Color color, double size) => Transform.rotate(
                angle: sway,
                child: Transform(
                  alignment: Alignment.bottomCenter,
                  transform: Matrix4.diagonal3Values(
                    scaleX * flamePop,
                    scaleY * flamePop,
                    1.0,
                  ),
                  child: FlameIcon(size: size, color: color),
                ),
              );

          return Stack(
            alignment: Alignment.center,
            children: [
              // Лучи-солнце: наезжают и медленно вращаются.
              Opacity(
                opacity: raysOpacity,
                child: Transform.rotate(
                  angle: _spin.value * 2 * math.pi,
                  child: Transform.scale(
                    scale: raysGrow,
                    child: CustomPaint(
                      size: const Size(_area, _area),
                      painter: _SunburstPainter(
                        color: AppColors.gold,
                        opacity: 0.16,
                        rayCount: 12,
                      ),
                    ),
                  ),
                ),
              ),
              // Вспышка появления: заливка + расходящееся кольцо.
              if (flashT < 1) ...[
                Opacity(
                  opacity: (1 - flashT) * 0.5,
                  child: Transform.scale(
                    scale: 0.2 + flashT * 1.6,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.gold,
                      ),
                      child: SizedBox(width: 70, height: 70),
                    ),
                  ),
                ),
                Transform.scale(
                  scale: 0.2 + flashT * 2.2,
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.gold
                            .withValues(alpha: (1 - flashT) * 0.6),
                        width: 3,
                      ),
                    ),
                  ),
                ),
              ],
              // Искры, взлетающие вверх (по фазе цикла, со сдвигом).
              ..._buildEmbers(a),
              // Пламя: основной силуэт + светлое мерцающее ядро.
              Opacity(opacity: flameOpacity, child: flame(AppColors.gold, 64)),
              Opacity(
                opacity: flameOpacity * coreOpacity,
                child: flame(const Color(0xFFFFE0B2), 40),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildEmbers(double a) {
    // Небольшие искры у пламени: восходят и гаснут, с разными фазами и сдвигом.
    const configs = <List<double>>[
      [0.0, -14],
      [0.33, 10],
      [0.66, -4],
    ];
    return configs.map((c) {
      final p = (a + c[0]) % 1.0;
      // Прозрачность ~0 на краях цикла — стык подъёма незаметен.
      final op = p < 0.15 ? p / 0.15 : (1 - (p - 0.15) / 0.85);
      final dy = 8 - p * 46;
      final scale = 1.0 - p * 0.65;
      return Transform.translate(
        offset: Offset(c[1], dy),
        child: Opacity(
          opacity: _clamp01(op),
          child: Transform.scale(
            scale: scale,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold,
              ),
              child: SizedBox(width: 7, height: 7),
            ),
          ),
        ),
      );
    }).toList();
  }
}

/// Лучи-«солнце» за пламенем: [rayCount] тонких треугольников от центра.
class _SunburstPainter extends CustomPainter {
  final Color color;
  final double opacity;
  final int rayCount;

  const _SunburstPainter({
    required this.color,
    required this.opacity,
    required this.rayCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outer = size.width / 2;
    final inner = outer * 0.46;
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;
    final half = (math.pi / rayCount) * 0.32;
    for (var i = 0; i < rayCount; i++) {
      final ang = (2 * math.pi / rayCount) * i - math.pi / 2;
      Offset at(double r, double da) =>
          center + Offset(math.cos(ang + da), math.sin(ang + da)) * r;
      final a1 = at(inner, -half);
      final a2 = at(outer, 0);
      final a3 = at(inner, half);
      final path = Path()
        ..moveTo(a1.dx, a1.dy)
        ..lineTo(a2.dx, a2.dy)
        ..lineTo(a3.dx, a3.dy)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SunburstPainter old) =>
      old.opacity != opacity || old.color != color || old.rayCount != rayCount;
}

class _RecordChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.goldLightSurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.emoji_events_rounded, size: 14, color: AppColors.gold),
          const SizedBox(width: 6),
          Text(
            appL10n.personalRecord,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.gold,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  final List<DateTime> days;
  final DateTime today;
  final bool Function(DateTime) isActive;
  final List<String> labels;

  const _WeekStrip({
    required this.days,
    required this.today,
    required this.isActive,
    required this.labels,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (i) {
        final d = days[i];
        final active = isActive(d);
        final isToday = d.isAtSameMomentAs(today);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // Единый стиль с карточкой на главной: активный день —
                // сплошной оранжевый, сегодняшний пустой — белый с контуром.
                color: active
                    ? AppColors.gold
                    : (isToday ? AppColors.white : Colors.transparent),
                shape: BoxShape.circle,
                border: Border.all(
                  // Сегодняшний без тренировки — чёрный контур, толщина как у всех.
                  color: active
                      ? AppColors.gold
                      : (isToday ? AppColors.primaryText : AppColors.divider),
                  width: 1.2,
                ),
              ),
              child: FlameIcon(
                size: 13,
                // Активный — белый; сегодня без тренировки — чёрный (в цвет
                // обводки); прочие пустые — светло-серый.
                color: active
                    ? AppColors.white
                    : (isToday ? AppColors.primaryText : AppColors.divider),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              labels[d.weekday - 1],
              style: TextStyle(
                fontSize: 11,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                color: isToday
                    ? AppColors.primaryText
                    : AppColors.secondaryText,
                height: 1.0,
              ),
            ),
          ],
        );
      }),
    );
  }
}
