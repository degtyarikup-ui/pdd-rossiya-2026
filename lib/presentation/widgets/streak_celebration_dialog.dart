import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/core/utils/weekday_labels.dart';
import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/flame_icon.dart';

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
  SoundEffectsService.instance.playStreak();
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
    final colors = AppColors.of(context);
    final s = widget.streak;
    // «Личный рекорд» — только если уже была серия выше единицы. На первый
    // день current=1==longest, но это не повод хвалить за «рекорд».
    final isNewRecord = s.current > 1 && s.current >= s.longest;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = s.weekStripDays(today: today);

    return Dialog(
      backgroundColor: colors.cardBackground,
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
              style: TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.6,
                height: 1.0,
                color: colors.primaryText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              appL10n.streakDaysWord(s.current),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colors.primaryText,
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
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: colors.secondaryText,
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
                  backgroundColor: colors.accent,
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

/// Эпичное появление огонька: взрывная вспышка-бурст → двойные вращающиеся
/// золотые лучи → многослойное пламя с градиентным огнём и раскалённым ядром
/// → взлетающие мерцающие искры и сияющие 4-конечные звёзды.
class _StreakFlameBurst extends StatefulWidget {
  const _StreakFlameBurst();

  @override
  State<_StreakFlameBurst> createState() => _StreakFlameBurstState();
}

class _StreakFlameBurstState extends State<_StreakFlameBurst>
    with TickerProviderStateMixin {
  late final AnimationController _entrance;
  late final AnimationController _ambient;
  late final AnimationController _spin;
  late final AnimationController _sparkle;

  static const double _area = 180;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 12000),
    )..repeat();
    _sparkle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _ambient.dispose();
    _spin.dispose();
    _sparkle.dispose();
    super.dispose();
  }

  double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _area,
      height: _area,
      child: AnimatedBuilder(
        animation: Listenable.merge([_entrance, _ambient, _spin, _sparkle]),
        builder: (context, _) {
          final e = _entrance.value; // появление 0..1
          final a = _ambient.value; // цикл горения 0..1
          final sp = _sparkle.value; // цикл мерцания звёзд 0..1
          final angle = a * 2 * math.pi;

          // Подпрогрессы появления
          final flamePop = Curves.elasticOut.transform(_clamp01(e / 0.85));
          final flameOpacity = _clamp01(e * 4);
          final raysGrow = Curves.easeOutBack.transform(_clamp01(e / 0.7));
          final raysOpacity = _clamp01(e / 0.5);
          final flashT = _clamp01(e / 0.35); // вспышка в первые 35%

          // Органическое мерцание пламени: сумма синусоид
          final flicker = math.sin(angle) * 0.50 +
              math.sin(angle * 3 + 1.2) * 0.30 +
              math.sin(angle * 2 + 0.5) * 0.20; // ≈ -1..1
          final f = (flicker + 1) / 2; // 0..1
          final scaleY = 1.0 + f * 0.12;
          final scaleX = 1.0 - f * 0.05;
          final swayOuter = math.sin(angle * 2) * 0.042; // ±2.4°
          final swayInner = math.sin(angle * 2 + 0.8) * -0.028;
          final corePulse = 0.40 + f * 0.60;

          // Отрисовка слоя пламени с градиентной заливкой
          Widget gradientFlame({
            required double size,
            required List<Color> colors,
            required double swayAngle,
            required double sX,
            required double sY,
          }) {
            return Transform.rotate(
              angle: swayAngle,
              child: Transform(
                alignment: Alignment.bottomCenter,
                transform: Matrix4.diagonal3Values(
                  sX * flamePop,
                  sY * flamePop,
                  1.0,
                ),
                child: ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (bounds) => LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: colors,
                  ).createShader(bounds),
                  child: FlameIcon(size: size, color: Colors.white),
                ),
              ),
            );
          }

          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Мягкая фоновая аура тепла
              Opacity(
                opacity: _clamp01(raysOpacity * (0.25 + f * 0.15)),
                child: Transform.scale(
                  scale: 0.85 + f * 0.20,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFFF9100).withValues(alpha: 0.35),
                          const Color(0xFFFFD600).withValues(alpha: 0.10),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.55, 1.0],
                      ),
                    ),
                  ),
                ),
              ),

              // Вращающиеся лучи-«солнце» (внешний золотой ярус)
              Opacity(
                opacity: raysOpacity,
                child: Transform.rotate(
                  angle: _spin.value * 2 * math.pi,
                  child: Transform.scale(
                    scale: raysGrow,
                    child: const CustomPaint(
                      size: Size(_area, _area),
                      painter: _SunburstPainter(
                        color: Color(0xFFFFB300),
                        opacity: 0.18,
                        rayCount: 16,
                      ),
                    ),
                  ),
                ),
              ),

              // Внутренний ярус лучей (вращается в обратную сторону)
              Opacity(
                opacity: raysOpacity * 0.7,
                child: Transform.rotate(
                  angle: -_spin.value * 2 * math.pi * 0.6,
                  child: Transform.scale(
                    scale: raysGrow * 0.75,
                    child: const CustomPaint(
                      size: Size(_area, _area),
                      painter: _SunburstPainter(
                        color: Color(0xFFFFD54F),
                        opacity: 0.22,
                        rayCount: 8,
                      ),
                    ),
                  ),
                ),
              ),

              // Взрывная вспышка и расширяющиеся кольца при появлении
              if (flashT < 1) ...[
                // Яркое белое ядро вспышки
                Opacity(
                  opacity: (1 - flashT) * 0.7,
                  child: Transform.scale(
                    scale: 0.3 + flashT * 1.8,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFFFF9C4),
                      ),
                    ),
                  ),
                ),
                // Внутреннее золотое кольцо
                Transform.scale(
                  scale: 0.2 + flashT * 2.0,
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFFFD600)
                            .withValues(alpha: (1 - flashT) * 0.8),
                        width: 3.5,
                      ),
                    ),
                  ),
                ),
                // Внешнее кольцо ударной волны
                Transform.scale(
                  scale: 0.4 + flashT * 2.6,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFFF6D00)
                            .withValues(alpha: (1 - flashT) * 0.5),
                        width: 2.0,
                      ),
                    ),
                  ),
                ),
              ],

              // Восходящие частицы-искры
              ..._buildEmbers(a),

              // Сияющие 4-конечные звёздочки вокруг пламени
              ..._buildSparkles(sp),

              // 1. Внешний слой: насыщенный градиентный огонь
              Opacity(
                opacity: flameOpacity,
                child: gradientFlame(
                  size: 86,
                  colors: const [
                    Color(0xFFFF2A00),
                    Color(0xFFFF6D00),
                    Color(0xFFFFD600),
                  ],
                  swayAngle: swayOuter,
                  sX: scaleX,
                  sY: scaleY,
                ),
              ),

              // 2. Средний слой: золотисто-янтарный лепесток
              Opacity(
                opacity: flameOpacity * 0.95,
                child: gradientFlame(
                  size: 64,
                  colors: const [
                    Color(0xFFFF8F00),
                    Color(0xFFFFEE58),
                  ],
                  swayAngle: swayInner,
                  sX: scaleX * 0.96,
                  sY: scaleY * 0.98,
                ),
              ),

              // 3. Внутреннее раскалённое бело-жёлтое ядро
              Opacity(
                opacity: flameOpacity * corePulse,
                child: gradientFlame(
                  size: 44,
                  colors: const [
                    Color(0xFFFFE082),
                    Color(0xFFFFFFFF),
                  ],
                  swayAngle: swayInner * 0.5,
                  sX: scaleX * 0.92,
                  sY: scaleY * 1.02,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildEmbers(double a) {
    // 6 восходящих искр с гармоническими синусными траекториями
    const configs = <List<double>>[
      [0.00, -18.0, 6.0, 50.0],
      [0.18, 14.0, 5.0, 58.0],
      [0.36, -8.0, 6.5, 66.0],
      [0.54, 18.0, 5.5, 52.0],
      [0.72, -22.0, 4.5, 62.0],
      [0.88, 8.0, 6.0, 70.0],
    ];

    return configs.map((c) {
      final phaseOffset = c[0];
      final baseX = c[1];
      final size = c[2];
      final maxDistance = c[3];

      final p = (a + phaseOffset) % 1.0;
      final op = p < 0.15 ? p / 0.15 : (1.0 - (p - 0.15) / 0.85);
      final dy = 12.0 - p * maxDistance;
      final dx = baseX + math.sin(p * math.pi * 2) * 5.0;
      final scale = 1.0 - p * 0.60;

      return Transform.translate(
        offset: Offset(dx, dy),
        child: Opacity(
          opacity: _clamp01(op),
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [
                    Color(0xFFFFF9C4),
                    Color(0xFFFFB300),
                    Color(0xFFFF6D00),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.4),
                  width: 0.5,
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _buildSparkles(double sp) {
    // 4 мерцающие 4-конечные звёздочки
    const sparkles = <List<double>>[
      [-48.0, -28.0, 16.0, 0.00],
      [46.0, -32.0, 18.0, 0.35],
      [-38.0, 24.0, 13.0, 0.65],
      [42.0, 18.0, 14.0, 0.85],
    ];

    return sparkles.map((s) {
      final x = s[0];
      final y = s[1];
      final starSize = s[2];
      final phase = s[3];

      final p = (sp + phase) % 1.0;
      // Синусоидальное сияние: 0 → 1 → 0
      final glow = math.sin(p * math.pi);
      final scale = 0.4 + glow * 0.7;
      final rot = p * math.pi * 0.5;

      return Positioned(
        left: _area / 2 + x - starSize / 2,
        top: _area / 2 + y - starSize / 2,
        child: Opacity(
          opacity: _clamp01(glow),
          child: Transform.rotate(
            angle: rot,
            child: Transform.scale(
              scale: scale,
              child: CustomPaint(
                size: Size(starSize, starSize),
                painter: const _SparkleStarPainter(color: Color(0xFFFFE082)),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }
}

/// 4-конечная сияющая бриллиантовая звёздочка
class _SparkleStarPainter extends CustomPainter {
  final Color color;

  const _SparkleStarPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;
    final inner = r * 0.22;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(cx, cy - r)
      ..quadraticBezierTo(cx, cy, cx + r, cy)
      ..quadraticBezierTo(cx, cy, cx, cy + r)
      ..quadraticBezierTo(cx, cy, cx - r, cy)
      ..quadraticBezierTo(cx, cy, cx, cy - r)
      ..close();

    canvas.drawPath(path, paint);

    // Белое яркое ядрышко
    final centerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), inner * 0.8, centerPaint);
  }

  @override
  bool shouldRepaint(covariant _SparkleStarPainter old) => old.color != color;
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
    final inner = outer * 0.42;
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;
    final half = (math.pi / rayCount) * 0.30;
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
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.goldLightSurface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.emoji_events_rounded, size: 14, color: colors.gold),
          const SizedBox(width: 6),
          Text(
            appL10n.personalRecord,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colors.gold,
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
    final colors = AppColors.of(context);
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
                // сплошной оранжевый, сегодняшний пустой — фон карточки с контуром.
                color: active
                    ? colors.gold
                    : (isToday ? colors.cardBackground : Colors.transparent),
                shape: BoxShape.circle,
                border: Border.all(
                  color: active
                      ? colors.gold
                      : (isToday ? colors.primaryText : colors.divider),
                  width: 1.2,
                ),
              ),
              child: FlameIcon(
                size: 13,
                color: active
                    ? AppColors.white
                    : (isToday ? colors.primaryText : colors.divider),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              labels[d.weekday - 1],
              style: TextStyle(
                fontSize: 11,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                color: isToday
                    ? colors.primaryText
                    : colors.secondaryText,
                height: 1.0,
              ),
            ),
          ],
        );
      }),
    );
  }
}
