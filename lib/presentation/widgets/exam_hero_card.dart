import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ExamCardConcept {
  signU(0, 'Знак «У»'),
  license(1, 'Водительские права'),
  speedometer(2, 'Спидометр 100%'),
  trafficLight(3, 'Зелёный светофор'),
  chronometer(4, 'Хронометр и знаки'),
  overpass(5, 'Парящая эстакада'),
  mainRoad(6, 'Главная дорога');

  final int id;
  final String title;
  const ExamCardConcept(this.id, this.title);

  static ExamCardConcept fromId(int id) {
    final validId = id.clamp(0, ExamCardConcept.values.length - 1);
    return ExamCardConcept.values[validId];
  }
}

class ExamHeroCard extends StatefulWidget {
  final double height;
  final VoidCallback onTap;
  final String questionsBadge;
  final String timeBadge;
  final String categoryBadge;
  final ExamCardConcept? forcedConcept;

  const ExamHeroCard({
    super.key,
    required this.height,
    required this.onTap,
    required this.questionsBadge,
    required this.timeBadge,
    required this.categoryBadge,
    this.forcedConcept,
  });

  static const String _prefKeyConcept = 'home_exam_concept_index';

  /// Загрузить и инкрементировать индекс концепта для следующей сессии.
  static Future<ExamCardConcept> getAndRotateConcept() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt(_prefKeyConcept) ?? 0;
      final next = (current + 1) % ExamCardConcept.values.length;
      await prefs.setInt(_prefKeyConcept, next);
      return ExamCardConcept.fromId(current);
    } catch (_) {
      return ExamCardConcept.signU;
    }
  }

  @override
  State<ExamHeroCard> createState() => _ExamHeroCardState();
}

class _ExamHeroCardState extends State<ExamHeroCard> {
  ExamCardConcept _concept = ExamCardConcept.signU;

  @override
  void initState() {
    super.initState();
    if (widget.forcedConcept != null) {
      _concept = widget.forcedConcept!;
    } else {
      _initConcept();
    }
  }

  Future<void> _initConcept() async {
    final concept = await ExamHeroCard.getAndRotateConcept();
    if (mounted) {
      setState(() => _concept = concept);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          HapticFeedbackHelper.tap();
          widget.onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          height: widget.height,
          decoration: BoxDecoration(
            color: colors.accent,
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cardW = constraints.maxWidth;
              final cardH = constraints.maxHeight;

              // Динамический расчёт размера слота под арт:
              // Арт занимает правую часть карточки и пропорционально масштабируется
              final artW = (cardW * 0.46).clamp(130.0, 220.0);
              final artH = cardH;

              return Stack(
                children: [
                  // Векторная иллюстрация в правом углу
                  Positioned(
                    right: 0,
                    bottom: 0,
                    width: artW,
                    height: artH,
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _buildPainterForConcept(_concept),
                        size: Size(artW, artH),
                      ),
                    ),
                  ),

                  // Текстовый контент (бейджи + заголовок)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: (cardH < 130) ? 10 : 14,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Верхний ряд бейджей
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: [
                              _buildBadge(widget.questionsBadge),
                              const SizedBox(width: 6),
                              _buildBadge(widget.timeBadge),
                              const SizedBox(width: 6),
                              _buildBadge(widget.categoryBadge),
                            ],
                          ),
                        ),

                        // Заголовок «Экзамен»
                        Row(
                          children: [
                            Text(
                              'Экзамен',
                              style: TextStyle(
                                fontSize: (cardH < 130) ? 22 : 26,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: -0.3,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  CustomPainter _buildPainterForConcept(ExamCardConcept concept) {
    switch (concept) {
      case ExamCardConcept.signU:
        return const _SignUPainter();
      case ExamCardConcept.license:
        return const _LicenseCardPainter();
      case ExamCardConcept.speedometer:
        return const _SpeedometerPainter();
      case ExamCardConcept.trafficLight:
        return const _TrafficLightPainter();
      case ExamCardConcept.chronometer:
        return const _ChronometerPainter();
      case ExamCardConcept.overpass:
        return const _OverpassPainter();
      case ExamCardConcept.mainRoad:
        return const _MainRoadSignPainter();
    }
  }
}

// ---------------------------------------------------------------------------
// 1. Концепт 01: Знак «У» в изометрии (со скруглёнными углами)
// ---------------------------------------------------------------------------
class _SignUPainter extends CustomPainter {
  const _SignUPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Центр знака (без артефактов дороги внизу)
    final cx = w * 0.62;
    final cy = h * 0.54;
    final signScale = (h / 140.0).clamp(0.7, 1.2);

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(-8 * math.pi / 180);
    canvas.scale(signScale);

    // Внешний скруглённый красный треугольник
    final redPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFED4621), Color(0xFFC02A0B)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(const Rect.fromLTWH(-55, -45, 110, 95))
      ..style = PaintingStyle.fill;

    final outerPath = _buildRoundedTriangle(
      top: const Offset(0, -46),
      bottomRight: const Offset(52, 42),
      bottomLeft: const Offset(-52, 42),
      radius: 9.0,
    );
    canvas.drawPath(outerPath, redPaint);

    // Внутренний скруглённый белый треугольник
    final whitePaint = Paint()
      ..color = const Color(0xFFF8FAFC)
      ..style = PaintingStyle.fill;

    final innerPath = _buildRoundedTriangle(
      top: const Offset(0, -29),
      bottomRight: const Offset(36, 33),
      bottomLeft: const Offset(-36, 33),
      radius: 5.5,
    );
    canvas.drawPath(innerPath, whitePaint);

    // Буква «У»
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'У',
        style: TextStyle(
          fontSize: 38,
          fontWeight: FontWeight.w900,
          color: Color(0xFF1E293B),
          fontFamily: 'sans-serif',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(-textPainter.width / 2, -10),
    );

    canvas.restore();
  }

  static Path _buildRoundedTriangle({
    required Offset top,
    required Offset bottomRight,
    required Offset bottomLeft,
    required double radius,
  }) {
    final path = Path();
    final vLT = top - bottomLeft;
    final dirLT = vLT / vLT.distance;
    final vTR = bottomRight - top;
    final dirTR = vTR / vTR.distance;
    final vRL = bottomLeft - bottomRight;
    final dirRL = vRL / vRL.distance;

    final start = bottomLeft + dirLT * radius;
    path.moveTo(start.dx, start.dy);
    path.lineTo(top.dx - dirLT.dx * radius, top.dy - dirLT.dy * radius);
    path.quadraticBezierTo(top.dx, top.dy, top.dx + dirTR.dx * radius, top.dy + dirTR.dy * radius);
    path.lineTo(bottomRight.dx - dirTR.dx * radius, bottomRight.dy - dirTR.dy * radius);
    path.quadraticBezierTo(bottomRight.dx, bottomRight.dy, bottomRight.dx + dirRL.dx * radius, bottomRight.dy + dirRL.dy * radius);
    path.lineTo(bottomLeft.dx - dirRL.dx * radius, bottomLeft.dy - dirRL.dy * radius);
    path.quadraticBezierTo(bottomLeft.dx, bottomLeft.dy, start.dx, start.dy);
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// 2. Концепт 02: Водительские права (License Card)
// ---------------------------------------------------------------------------
class _LicenseCardPainter extends CustomPainter {
  const _LicenseCardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.58;
    final cy = h * 0.54;
    final scale = (h / 140.0).clamp(0.7, 1.2);

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(-12 * math.pi / 180);
    canvas.scale(scale);

    // Пластиковая карточка
    final cardRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-60, -36, 120, 72),
      const Radius.circular(8),
    );
    final cardPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFF8FAFC), Color(0xFFE2E8F0)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(const Rect.fromLTWH(-60, -36, 120, 72));
    canvas.drawRRect(cardRect, cardPaint);

    // Рамка фото
    final photoRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-52, -26, 26, 32),
      const Radius.circular(4),
    );
    canvas.drawRRect(photoRect, Paint()..color = const Color(0xFFCBD5E1));

    // Силуэт на фото
    final avatarHead = Paint()..color = const Color(0xFF64748B);
    canvas.drawCircle(const Offset(-39, -15), 5.5, avatarHead);
    final avatarBody = Path()
      ..addOval(const Rect.fromLTWH(-48, -7, 18, 14));
    canvas.drawPath(avatarBody, avatarHead);

    // Строки текста
    final linePaint = Paint()..color = const Color(0xFF475569);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(-18, -24, 66, 4), const Radius.circular(2)),
      linePaint,
    );
    final subLinePaint = Paint()..color = const Color(0xFF94A3B8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(-18, -15, 48, 3.5), const Radius.circular(2)),
      subLinePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(-18, -7, 54, 3.5), const Radius.circular(2)),
      subLinePaint,
    );

    // Голографическая полоса
    final holoPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0x99EC4899),
          Color(0x993B82F6),
          Color(0x9910B981),
        ],
      ).createShader(const Rect.fromLTWH(-60, 14, 120, 10));
    canvas.drawRect(const Rect.fromLTWH(-60, 14, 120, 10), holoPaint);

    // Золотая точка-герб
    canvas.drawCircle(const Offset(-46, 19), 3, Paint()..color = const Color(0xFFF59E0B));

    // Надпись RUS
    final rusPainter = TextPainter(
      text: const TextSpan(
        text: 'RUS',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: Color(0xFF1E293B),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    rusPainter.paint(canvas, const Offset(36, 14));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// 3. Концепт 03: Спидометр (Скорость 89 км/ч)
// ---------------------------------------------------------------------------
class _SpeedometerPainter extends CustomPainter {
  const _SpeedometerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.58;
    final cy = h * 0.54;
    final scale = (h / 140.0).clamp(0.7, 1.2);

    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(scale);

    // Корпус спидометра (без артефактов полукругов слева)
    final gaugePaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset.zero, 44, gaugePaint);
    canvas.drawCircle(
      Offset.zero,
      44,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Фоновая шкала
    final bgArc = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      const Rect.fromLTWH(-33, -33, 66, 66),
      math.pi * 0.75,
      math.pi * 1.5,
      false,
      bgArc,
    );

    // Цветная шкала скорости (~89 из 120 км/ч)
    final speedArc = Paint()
      ..shader = const SweepGradient(
        colors: [Color(0xFF38BDF8), Color(0xFF10B981), Color(0xFFF59E0B)],
        stops: [0.0, 0.6, 1.0],
        transform: GradientRotation(math.pi * 0.75),
      ).createShader(const Rect.fromLTWH(-33, -33, 66, 66))
      ..strokeWidth = 5.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      const Rect.fromLTWH(-33, -33, 66, 66),
      math.pi * 0.75,
      math.pi * 1.15,
      false,
      speedArc,
    );

    // Стрелка на 89 км/ч (угол ~ 20 градусов выше горизонтали справа)
    final needleAngle = math.pi * 0.75 + math.pi * 1.15;
    final needleLen = 25.0;
    final needleEnd = Offset(
      math.cos(needleAngle) * needleLen,
      math.sin(needleAngle) * needleLen,
    );
    final needlePaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset.zero, needleEnd, needlePaint);

    // Центральный колпачок
    canvas.drawCircle(Offset.zero, 6.0, Paint()..color = const Color(0xFFF8FAFC));
    canvas.drawCircle(Offset.zero, 3.0, Paint()..color = const Color(0xFF0F172A));

    // Число скорости «89»
    final speedPainter = TextPainter(
      text: const TextSpan(
        text: '89',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          letterSpacing: -0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    speedPainter.paint(canvas, Offset(-speedPainter.width / 2, 10));

    // Подпись «км/ч»
    final unitPainter = TextPainter(
      text: const TextSpan(
        text: 'км/ч',
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w600,
          color: Color(0xFF94A3B8),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    unitPainter.paint(canvas, Offset(-unitPainter.width / 2, 26));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// 4. Концепт 04: Зелёный светофор (3D Traffic Light)
// ---------------------------------------------------------------------------
class _TrafficLightPainter extends CustomPainter {
  const _TrafficLightPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.60;
    final cy = h * 0.52;
    final scale = (h / 140.0).clamp(0.7, 1.2);

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(-6 * math.pi / 180);
    canvas.scale(scale);

    // Зелёный светящийся ореол
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF34D399).withValues(alpha: 0.5),
          const Color(0xFF2BC280).withValues(alpha: 0.0),
        ],
      ).createShader(const Rect.fromLTWH(-36, 10, 72, 72));
    canvas.drawCircle(const Offset(0, 26), 36, glowPaint);

    // Корпус светофора
    final bodyRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-20, -46, 40, 92),
      const Radius.circular(12),
    );
    canvas.drawRRect(bodyRect, Paint()..color = const Color(0xFF0F172A));
    canvas.drawRRect(
      bodyRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Красный сигнал (выкл)
    canvas.drawCircle(const Offset(0, -28), 9.5, Paint()..color = const Color(0xFF334155));
    // Жёлтый сигнал (выкл)
    canvas.drawCircle(const Offset(0, -1), 9.5, Paint()..color = const Color(0xFF334155));
    // Зелёный сигнал (вкл, яркий)
    canvas.drawCircle(const Offset(0, 26), 10.5, Paint()..color = const Color(0xFF2BC280));
    canvas.drawCircle(const Offset(0, 26), 6.5, Paint()..color = const Color(0xFF6EE7B7));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// 5. Концепт 09: Хронометр и знаки
// ---------------------------------------------------------------------------
class _ChronometerPainter extends CustomPainter {
  const _ChronometerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.60;
    final cy = h * 0.54;
    final scale = (h / 140.0).clamp(0.7, 1.2);

    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(scale);

    // Маленький знак «Главная дорога» слева вверху
    canvas.save();
    canvas.translate(-42, -28);
    canvas.rotate(-15 * math.pi / 180);
    final diamondPath = Path()
      ..moveTo(0, -11)
      ..lineTo(11, 0)
      ..lineTo(0, 11)
      ..lineTo(-11, 0)
      ..close();
    canvas.drawPath(diamondPath, Paint()..color = const Color(0xFFF8FAFC));
    final diamondInner = Path()
      ..moveTo(0, -8)
      ..lineTo(8, 0)
      ..lineTo(0, 8)
      ..lineTo(-8, 0)
      ..close();
    canvas.drawPath(diamondInner, Paint()..color = const Color(0xFFFFA53C));
    canvas.restore();

    // Маленький красный треугольник справа вверху
    canvas.save();
    canvas.translate(44, -20);
    canvas.rotate(14 * math.pi / 180);
    final triPath = Path()
      ..moveTo(0, -10)
      ..lineTo(10, 8)
      ..lineTo(-10, 8)
      ..close();
    canvas.drawPath(triPath, Paint()..color = const Color(0xFFED4621));
    final triInner = Path()
      ..moveTo(0, -6)
      ..lineTo(6, 5)
      ..lineTo(-6, 5)
      ..close();
    canvas.drawPath(triInner, Paint()..color = Colors.white);
    canvas.restore();

    // Корпус секундомера
    canvas.drawCircle(Offset.zero, 36, Paint()..color = const Color(0xFF0F172A));
    canvas.drawCircle(
      Offset.zero,
      36,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Верхняя кнопка
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(-5, -42, 10, 7), const Radius.circular(2)),
      Paint()..color = const Color(0xFF94A3B8),
    );

    // Пунктирный циферблат
    canvas.drawCircle(
      Offset.zero,
      27,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Стрелка
    canvas.drawLine(
      Offset.zero,
      const Offset(14, -14),
      Paint()
        ..color = const Color(0xFF38BDF8)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(Offset.zero, 4, Paint()..color = const Color(0xFF38BDF8));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// 6. Концепт 10: Парящая эстакада (С белой прерывистой разметкой и PIN-маркером)
// ---------------------------------------------------------------------------
class _OverpassPainter extends CustomPainter {
  const _OverpassPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Нижняя трасса: плавно уходит за границы
    final lowerRoad = Path()
      ..moveTo(w * 0.30, -h * 0.1)
      ..quadraticBezierTo(w * 0.65, h * 0.5, w * 0.92, h * 1.15);

    canvas.drawPath(
      lowerRoad,
      Paint()
        ..color = const Color(0xFF0F172A).withValues(alpha: 0.8)
        ..strokeWidth = 18
        ..style = PaintingStyle.stroke,
    );
    _drawDashedPath(
      canvas,
      lowerRoad,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.4)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke,
      dashLen: 6,
      spaceLen: 5,
    );

    // Верхняя парящая эстакада: плавно входит снизу-слева и уходит за правый верхний край
    final upperRoad = Path()
      ..moveTo(w * 0.05, h * 1.2)
      ..cubicTo(w * 0.42, h * 0.98, w * 0.62, h * 0.48, w * 1.15, h * 0.15);

    // Полотно эстакады
    canvas.drawPath(
      upperRoad,
      Paint()
        ..color = const Color(0xFF1E293B)
        ..strokeWidth = 24
        ..style = PaintingStyle.stroke,
    );

    // Белая прерывистая осевая разметка
    _drawDashedPath(
      canvas,
      upperRoad,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke,
      dashLen: 7,
      spaceLen: 5,
    );

    // Локационный PIN (как на картах) на верхней трассе
    _drawMapPin(canvas, Offset(w * 0.82, h * 0.38), 1.1);
  }

  static void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dashLen,
    required double spaceLen,
  }) {
    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final double next = (distance + dashLen).clamp(0.0, metric.length);
        final segment = metric.extractPath(distance, next);
        canvas.drawPath(segment, paint);
        distance += dashLen + spaceLen;
      }
    }
  }

  static void _drawMapPin(Canvas canvas, Offset tip, double scale) {
    canvas.save();
    canvas.translate(tip.dx, tip.dy);
    canvas.scale(scale);

    // Форма PIN (остриё вниз в точку (0, 0))
    final pinPath = Path()
      ..moveTo(0, 0)
      ..cubicTo(-4, -5, -8, -10, -8, -15)
      ..arcToPoint(
        const Offset(8, -15),
        radius: const Radius.circular(8),
        clockwise: true,
      )
      ..cubicTo(8, -10, 4, -5, 0, 0)
      ..close();

    // Тень под пином
    canvas.drawOval(
      const Rect.fromLTWH(-5, -1.5, 10, 3),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );

    // Красный корпус маркера
    final pinPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFED4621), Color(0xFFC02A0B)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(const Rect.fromLTWH(-8, -23, 16, 23))
      ..style = PaintingStyle.fill;
    canvas.drawPath(pinPath, pinPaint);

    // Белая точка внутри
    canvas.drawCircle(const Offset(0, -15), 3.2, Paint()..color = Colors.white);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// 7. Концепт 11 (Новый): Знак «Главная дорога» (2.1 со скруглениями, крупнее)
// ---------------------------------------------------------------------------
class _MainRoadSignPainter extends CustomPainter {
  const _MainRoadSignPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.60;
    final cy = h * 0.54;
    // Увеличенный масштаб
    final scale = (h / 140.0).clamp(0.75, 1.25);

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(-10 * math.pi / 180);
    canvas.scale(scale);

    // Внешний скруглённый белый ромб (без артефактов внизу)
    const double outerSize = 47.0;
    const double cornerRadius = 6.5;
    final outerDiamond = _buildRoundedDiamond(outerSize, cornerRadius);

    // Мягкая подсветка/тень
    canvas.drawPath(
      outerDiamond,
      Paint()
        ..color = const Color(0xFF0F172A).withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    canvas.drawPath(
      outerDiamond,
      Paint()
        ..color = const Color(0xFFF8FAFC)
        ..style = PaintingStyle.fill,
    );

    // Внутренний скруглённый насыщенный жёлтый ромб
    const double innerSize = 34.0;
    final innerDiamond = _buildRoundedDiamond(innerSize, 4.5);
    final yellowPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFDE047), Color(0xFFF59E0B)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(const Rect.fromLTWH(-innerSize, -innerSize, innerSize * 2, innerSize * 2))
      ..style = PaintingStyle.fill;
    canvas.drawPath(innerDiamond, yellowPaint);

    canvas.restore();
  }

  static Path _buildRoundedDiamond(double s, double r) {
    final path = Path();
    final d = r / 1.4142;
    path.moveTo(d, -s + d);
    path.lineTo(s - d, -d);
    path.quadraticBezierTo(s, 0, s - d, d);
    path.lineTo(d, s - d);
    path.quadraticBezierTo(0, s, -d, s - d);
    path.lineTo(-s + d, d);
    path.quadraticBezierTo(-s, 0, -s + d, -d);
    path.lineTo(-d, -s + d);
    path.quadraticBezierTo(0, -s, d, -s + d);
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
