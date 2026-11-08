import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ExamCardConcept {
  signU(0),
  license(1),
  speedometer(2),
  trafficLight(3),
  chronometer(4),
  overpass(5),
  mainRoad(6),
  steeringWheel(7),
  cone(8),
  carKey(9),
  car(10),
  answerSheet(11);

  final int id;
  const ExamCardConcept(this.id);

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

  /// Самое большое положение картинки, при котором она не задевает текст и
  /// края карточки. Границы считаются по кругу вокруг рисунка: углы у всех
  /// картинок свободны, поэтому она может подойти к бейджам по диагонали.
  static Rect fitArt({
    required Size card,
    required Rect badges,
    required Rect title,
  }) {
    const margin = 6.0;
    const gap = 4.0;
    const reach = _ExamArtPainter.artSize / 2;
    const halfHeight = 54.0;
    const maxScale = 1.2;
    const minScale = 0.45;

    double distance(Rect rect, Offset point) {
      final dx = math.max(
        math.max(rect.left - point.dx, point.dx - rect.right),
        0.0,
      );
      final dy = math.max(
        math.max(rect.top - point.dy, point.dy - rect.bottom),
        0.0,
      );
      return math.sqrt(dx * dx + dy * dy);
    }

    Rect at(Offset center, double scale) =>
        Rect.fromCircle(center: center, radius: reach * scale);

    for (var scale = maxScale; scale >= minScale; scale -= 0.01) {
      final x = card.width - margin - reach * scale;
      final lowest = card.height - margin - halfHeight * scale;
      for (final y in [math.min(card.height * 0.53, lowest), lowest]) {
        final clear = reach * scale + gap;
        if (y - halfHeight * scale >= margin &&
            distance(badges, Offset(x, y)) >= clear &&
            distance(title, Offset(x, y)) >= clear) {
          return at(Offset(x, y), scale);
        }
      }
    }
    return at(
      Offset(
        card.width - margin - reach * minScale,
        card.height - margin - halfHeight * minScale,
      ),
      minScale,
    );
  }

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

              final compact = cardH < 130;
              final verticalPadding = compact ? 10.0 : 14.0;
              final titleStyle = _titleStyle(compact);
              final art = _placeArt(
                context,
                card: Size(cardW, cardH),
                verticalPadding: verticalPadding,
                titleStyle: titleStyle,
              );

              return Stack(
                children: [
                  // Векторная иллюстрация в правом углу
                  Positioned.fromRect(
                    rect: art,
                    child: IgnorePointer(
                      child: CustomPaint(
                        key: const ValueKey('exam-hero-art'),
                        painter: _buildPainterForConcept(_concept),
                      ),
                    ),
                  ),

                  // Текстовый контент (бейджи + заголовок)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: _horizontalPadding,
                      vertical: verticalPadding,
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
                              const SizedBox(width: _badgeGap),
                              _buildBadge(widget.timeBadge),
                              const SizedBox(width: _badgeGap),
                              _buildBadge(widget.categoryBadge),
                            ],
                          ),
                        ),

                        // Заголовок «Экзамен»
                        Row(children: [Text(appL10n.exam, style: titleStyle)]),
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

  static const double _horizontalPadding = 18;
  static const double _badgeGap = 6;
  static const EdgeInsets _badgePadding = EdgeInsets.symmetric(
    horizontal: 10,
    vertical: 5,
  );
  static const TextStyle _badgeStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    letterSpacing: 0.2,
  );

  static TextStyle _titleStyle(bool compact) => TextStyle(
    fontSize: compact ? 22 : 26,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    letterSpacing: -0.3,
    height: 1.1,
  );

  /// Измеряет бейджи и заголовок с учётом языка и масштаба шрифта в системе
  /// и подбирает место картинки так, чтобы она их не задевала.
  Rect _placeArt(
    BuildContext context, {
    required Size card,
    required double verticalPadding,
    required TextStyle titleStyle,
  }) {
    final textScaler = MediaQuery.textScalerOf(context);
    final baseStyle = DefaultTextStyle.of(context).style;
    Size measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: baseStyle.merge(style)),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      final size = painter.size;
      painter.dispose();
      return size;
    }

    final badges = [
      widget.questionsBadge,
      widget.timeBadge,
      widget.categoryBadge,
    ].map((text) => measure(text, _badgeStyle));
    final badgesWidth = badges.fold<double>(
      _badgeGap * 2,
      (sum, size) => sum + size.width + _badgePadding.horizontal,
    );
    final badgesHeight =
        badges.map((size) => size.height).reduce(math.max) +
        _badgePadding.vertical;
    final title = measure(appL10n.exam, titleStyle);

    return ExamHeroCard.fitArt(
      card: card,
      badges: Rect.fromLTWH(
        _horizontalPadding,
        verticalPadding,
        math.min(badgesWidth, card.width - _horizontalPadding * 2),
        badgesHeight,
      ),
      title: Rect.fromLTWH(
        _horizontalPadding,
        card.height - verticalPadding - title.height,
        title.width,
        title.height,
      ),
    );
  }

  Widget _buildBadge(String text) {
    return Container(
      padding: _badgePadding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: _badgeStyle),
    );
  }

  static CustomPainter _buildPainterForConcept(ExamCardConcept concept) {
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
      case ExamCardConcept.steeringWheel:
        return const _SteeringWheelPainter();
      case ExamCardConcept.cone:
        return const _ConePainter();
      case ExamCardConcept.carKey:
        return const _CarKeyPainter();
      case ExamCardConcept.car:
        return const _CarPainter();
      case ExamCardConcept.answerSheet:
        return const _AnswerSheetPainter();
    }
  }
}

/// The same lightweight vector artwork used by the phone exam card.
class ExamHeroArtwork extends StatelessWidget {
  const ExamHeroArtwork({super.key, this.concept = ExamCardConcept.license});
  final ExamCardConcept concept;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _ExamHeroCardState._buildPainterForConcept(concept),
    size: Size.infinite,
  );
}

// ---------------------------------------------------------------------------
// Общий стиль иллюстраций: плоские формы без теней и контуров, одна палитра,
// один размер в единицах рисунка. Мягкое свечение — только у того, что
// светится на самом деле: сигналов, фар, подсветки приборов.
// ---------------------------------------------------------------------------
abstract final class _ArtColors {
  static const ink = Color(0xFF0B2C66);
  static const paper = Color(0xFFFFFFFF);
  static const mist = Color(0xFFCFE2FF);
  static const orange = Color(0xFFFF8F1F);
  static const red = Color(0xFFEF4A2B);
  static const green = Color(0xFF2BC280);
  static const yellow = Color(0xFFFFC233);
}

Paint _fill(Color color) => Paint()..color = color;

Paint _stroke(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

RRect _rrect(double l, double t, double w, double h, double r) =>
    RRect.fromRectAndRadius(Rect.fromLTWH(l, t, w, h), Radius.circular(r));

abstract class _ExamArtPainter extends CustomPainter {
  const _ExamArtPainter({this.tilt = 0});

  /// Наклон картинки в градусах.
  final double tilt;

  /// Сторона квадрата в единицах рисунка; центр рисунка — в центре квадрата.
  static const double artSize = 124;

  void paintArt(Canvas canvas);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(math.min(size.shortestSide / artSize, 1.25));
    canvas.rotate(tilt * math.pi / 180);
    paintArt(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void _drawGlow(
  Canvas canvas,
  Offset center,
  double radius,
  Color color, {
  double alpha = 0.55,
}) {
  final rect = Rect.fromCircle(center: center, radius: radius);
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: alpha),
          color.withValues(alpha: 0),
        ],
      ).createShader(rect),
  );
}

Path _roundedPolygon(List<Offset> points, double radius) {
  final path = Path();
  for (var i = 0; i < points.length; i++) {
    final corner = points[i];
    final previous = points[(i + points.length - 1) % points.length];
    final next = points[(i + 1) % points.length];
    final toPrevious = previous - corner;
    final toNext = next - corner;
    final entry = corner + toPrevious / toPrevious.distance * radius;
    final exit = corner + toNext / toNext.distance * radius;
    if (i == 0) {
      path.moveTo(entry.dx, entry.dy);
    } else {
      path.lineTo(entry.dx, entry.dy);
    }
    path.quadraticBezierTo(corner.dx, corner.dy, exit.dx, exit.dy);
  }
  return path..close();
}

Path _diamond(double size, double radius) => _roundedPolygon([
  Offset(0, -size),
  Offset(size, 0),
  Offset(0, size),
  Offset(-size, 0),
], radius);

void _drawCheck(Canvas canvas, Offset center, double size, double width) {
  canvas.drawPath(
    Path()
      ..moveTo(center.dx - size, center.dy + size * 0.05)
      ..lineTo(center.dx - size * 0.28, center.dy + size * 0.72)
      ..lineTo(center.dx + size, center.dy - size * 0.68),
    _stroke(_ArtColors.paper, width),
  );
}

// Знак «Учебное транспортное средство»
class _SignUPainter extends _ExamArtPainter {
  const _SignUPainter() : super(tilt: -6);

  @override
  void paintArt(Canvas canvas) {
    canvas.drawPath(
      _roundedPolygon(const [
        Offset(0, -47),
        Offset(50, 39),
        Offset(-50, 39),
      ], 9),
      _fill(_ArtColors.red),
    );
    canvas.drawPath(
      _roundedPolygon(const [
        Offset(0, -28),
        Offset(34, 30),
        Offset(-34, 30),
      ], 5),
      _fill(_ArtColors.paper),
    );
    final letter = TextPainter(
      text: const TextSpan(
        text: 'У',
        style: TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: 34,
          fontWeight: FontWeight.w800,
          color: _ArtColors.ink,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    letter.paint(canvas, Offset(-letter.width / 2, -14));
  }
}

// Водительское удостоверение
class _LicenseCardPainter extends _ExamArtPainter {
  const _LicenseCardPainter() : super(tilt: -10);

  @override
  void paintArt(Canvas canvas) {
    canvas.drawRRect(_rrect(-51, -33, 102, 66, 10), _fill(_ArtColors.paper));
    canvas.drawRRect(_rrect(-42, -24, 30, 36, 6), _fill(_ArtColors.mist));
    canvas.drawCircle(const Offset(-27, -12), 6.5, _fill(_ArtColors.ink));
    canvas.drawRRect(_rrect(-36, -3, 18, 15, 6), _fill(_ArtColors.ink));
    canvas.drawRRect(_rrect(-4, -23, 46, 6, 3), _fill(_ArtColors.ink));
    canvas.drawRRect(_rrect(-4, -10, 38, 5, 2.5), _fill(_ArtColors.mist));
    canvas.drawRRect(_rrect(-4, 1, 42, 5, 2.5), _fill(_ArtColors.mist));
    canvas.drawRRect(_rrect(-42, 18, 84, 7, 3.5), _fill(_ArtColors.orange));
  }
}

// Спидометр
class _SpeedometerPainter extends _ExamArtPainter {
  const _SpeedometerPainter();

  @override
  void paintArt(Canvas canvas) {
    const start = math.pi * 0.75;
    const sweep = math.pi * 1.5;
    const value = 0.68;
    const arc = Rect.fromLTWH(-33, -33, 66, 66);

    canvas.drawCircle(Offset.zero, 47, _fill(_ArtColors.ink));
    canvas.drawArc(
      arc,
      start,
      sweep,
      false,
      _stroke(Colors.white.withValues(alpha: 0.2), 7),
    );
    canvas.drawArc(
      arc,
      start,
      sweep * value,
      false,
      _stroke(_ArtColors.orange.withValues(alpha: 0.7), 9)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawArc(
      arc,
      start,
      sweep * value,
      false,
      _stroke(_ArtColors.orange, 7),
    );

    final angle = start + sweep * value;
    canvas.drawLine(
      Offset.zero,
      Offset(math.cos(angle) * 22, math.sin(angle) * 22),
      _stroke(_ArtColors.paper, 4),
    );
    canvas.drawCircle(Offset.zero, 6.5, _fill(_ArtColors.paper));
  }
}

// Светофор
class _TrafficLightPainter extends _ExamArtPainter {
  const _TrafficLightPainter() : super(tilt: -6);

  @override
  void paintArt(Canvas canvas) {
    canvas.drawRRect(_rrect(-23, -50, 46, 100, 18), _fill(_ArtColors.ink));
    final off = _fill(Colors.white.withValues(alpha: 0.18));
    canvas.drawCircle(const Offset(0, -29), 11, off);
    canvas.drawCircle(const Offset(0, 0), 11, off);
    _drawGlow(canvas, const Offset(0, 29), 42, _ArtColors.green, alpha: 0.65);
    canvas.drawCircle(const Offset(0, 29), 12, _fill(_ArtColors.green));
  }
}

// Секундомер
class _ChronometerPainter extends _ExamArtPainter {
  const _ChronometerPainter() : super(tilt: 8);

  @override
  void paintArt(Canvas canvas) {
    const center = Offset(0, 5);
    canvas.drawRRect(_rrect(-5, -49, 10, 12, 3), _fill(_ArtColors.ink));
    canvas.drawRRect(_rrect(-11, -53, 22, 8, 4), _fill(_ArtColors.ink));
    canvas.drawCircle(center, 44, _fill(_ArtColors.ink));
    canvas.drawCircle(center, 35, _fill(_ArtColors.paper));

    // Заполненная часть циферблата показывает прошедшее время
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 28),
      -math.pi / 2,
      math.pi * 0.72,
      true,
      _fill(_ArtColors.mist),
    );
    final angle = -math.pi / 2 + math.pi * 0.72;
    canvas.drawLine(
      center,
      center + Offset(math.cos(angle) * 27, math.sin(angle) * 27),
      _stroke(_ArtColors.orange, 4),
    );
    canvas.drawCircle(center, 5, _fill(_ArtColors.ink));
  }
}

// Дорога с меткой
class _OverpassPainter extends _ExamArtPainter {
  const _OverpassPainter();

  @override
  void paintArt(Canvas canvas) {
    // Дорога приходит снизу и уходит за правый край карточки
    final road = Path()
      ..moveTo(-34, 130)
      ..cubicTo(-36, 50, -2, 46, 10, 14)
      ..cubicTo(20, -12, 44, -26, 150, -24);

    canvas.drawPath(
      road,
      _stroke(_ArtColors.ink, 28)..strokeCap = StrokeCap.butt,
    );
    _drawDashes(canvas, road, _stroke(_ArtColors.paper, 2.6));

    // Метка на дороге
    canvas.save();
    canvas.translate(10, 14);
    final pin = Path()
      ..moveTo(0, 0)
      ..cubicTo(-6, -8, -15, -17, -15, -28)
      ..arcToPoint(const Offset(15, -28), radius: const Radius.circular(15))
      ..cubicTo(15, -17, 6, -8, 0, 0)
      ..close();
    canvas.drawPath(pin, _fill(_ArtColors.red));
    canvas.drawCircle(const Offset(0, -28), 6, _fill(_ArtColors.paper));
    canvas.restore();
  }

  static void _drawDashes(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      for (var d = 4.0; d < metric.length; d += 16) {
        canvas.drawPath(metric.extractPath(d, d + 7), paint);
      }
    }
  }
}

// Знак «Главная дорога»
class _MainRoadSignPainter extends _ExamArtPainter {
  const _MainRoadSignPainter() : super(tilt: -6);

  @override
  void paintArt(Canvas canvas) {
    canvas.drawPath(_diamond(50, 8), _fill(_ArtColors.paper));
    canvas.drawPath(_diamond(35, 5), _fill(_ArtColors.yellow));
  }
}

// Руль
class _SteeringWheelPainter extends _ExamArtPainter {
  const _SteeringWheelPainter() : super(tilt: -12);

  @override
  void paintArt(Canvas canvas) {
    final ink = _fill(_ArtColors.ink);
    canvas.drawCircle(Offset.zero, 42, _stroke(_ArtColors.ink, 13));
    canvas.drawRect(const Rect.fromLTWH(-40, -7, 80, 14), ink);
    canvas.drawRect(const Rect.fromLTWH(-7, 0, 14, 40), ink);
    canvas.drawCircle(Offset.zero, 18, ink);
    canvas.drawPath(_diamond(10, 2), _fill(_ArtColors.yellow));
    canvas.drawArc(
      const Rect.fromLTWH(-42, -42, 84, 84),
      -math.pi / 2 - 0.1,
      0.2,
      false,
      Paint()
        ..color = _ArtColors.orange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 13,
    );
  }
}

// Дорожный конус
class _ConePainter extends _ExamArtPainter {
  const _ConePainter() : super(tilt: 4);

  @override
  void paintArt(Canvas canvas) {
    final body = _roundedPolygon(const [
      Offset(-6, -52),
      Offset(6, -52),
      Offset(35, 40),
      Offset(-35, 40),
    ], 5);
    canvas.drawRRect(_rrect(-52, 35, 104, 15, 7.5), _fill(_ArtColors.orange));
    canvas.save();
    canvas.clipPath(body);
    canvas.drawPath(body, _fill(_ArtColors.orange));
    final stripe = _fill(_ArtColors.paper);
    canvas.drawRect(const Rect.fromLTWH(-40, -24, 80, 15), stripe);
    canvas.drawRect(const Rect.fromLTWH(-40, 8, 80, 15), stripe);
    canvas.restore();
  }
}

// Ключ от машины
class _CarKeyPainter extends _ExamArtPainter {
  const _CarKeyPainter() : super(tilt: 34);

  @override
  void paintArt(Canvas canvas) {
    canvas.drawCircle(const Offset(0, -46), 9, _stroke(_ArtColors.paper, 3.5));
    canvas.drawPath(
      _roundedPolygon(const [
        Offset(-6.5, 14),
        Offset(6.5, 14),
        Offset(6.5, 42),
        Offset(1.5, 42),
        Offset(6.5, 49),
        Offset(1.5, 54),
        Offset(1.5, 60),
        Offset(-6.5, 60),
      ], 1.5),
      _fill(_ArtColors.paper),
    );
    canvas.drawRRect(_rrect(-23, -40, 46, 62, 17), _fill(_ArtColors.ink));
    _drawGlow(canvas, const Offset(0, -21), 22, _ArtColors.orange, alpha: 0.6);
    canvas.drawCircle(const Offset(0, -21), 8, _fill(_ArtColors.orange));
    canvas.drawCircle(
      const Offset(0, 2),
      8,
      _fill(Colors.white.withValues(alpha: 0.22)),
    );
  }
}

// Красный автомобиль спереди с включёнными фарами
class _CarPainter extends _ExamArtPainter {
  const _CarPainter();

  static const Color _redDark = Color(0xFFC9341A);

  @override
  void paintArt(Canvas canvas) {
    canvas.translate(0, 2);

    // Колёса
    final ink = _fill(_ArtColors.ink);
    canvas.drawRRect(_rrect(-47, 24, 19, 22, 7), ink);
    canvas.drawRRect(_rrect(28, 24, 19, 22, 7), ink);

    // Зеркала
    final mirror = _fill(_redDark);
    canvas.drawRRect(_rrect(-56, -12, 13, 9, 4.5), mirror);
    canvas.drawRRect(_rrect(43, -12, 13, 9, 4.5), mirror);

    // Кузов
    final body = Path()
      ..moveTo(-30, -38)
      ..quadraticBezierTo(0, -43, 30, -38)
      ..quadraticBezierTo(37, -36, 40, -29)
      ..lineTo(45, -11)
      ..quadraticBezierTo(54, -7, 54, 4)
      ..lineTo(54, 23)
      ..quadraticBezierTo(54, 34, 43, 34)
      ..lineTo(-43, 34)
      ..quadraticBezierTo(-54, 34, -54, 23)
      ..lineTo(-54, 4)
      ..quadraticBezierTo(-54, -7, -45, -11)
      ..lineTo(-40, -29)
      ..quadraticBezierTo(-37, -36, -30, -38)
      ..close();
    canvas.drawPath(body, _fill(_ArtColors.red));

    // Лобовое стекло
    canvas.drawPath(
      Path()
        ..moveTo(-27, -31)
        ..quadraticBezierTo(0, -35, 27, -31)
        ..quadraticBezierTo(31, -30, 32, -26)
        ..lineTo(36, -13)
        ..quadraticBezierTo(0, -8, -36, -13)
        ..lineTo(-32, -26)
        ..quadraticBezierTo(-31, -30, -27, -31)
        ..close(),
      ink,
    );

    // Фары
    for (final x in const [-36.0, 36.0]) {
      final center = Offset(x, 6);
      _drawGlow(canvas, center, 19, _ArtColors.yellow, alpha: 0.5);
      canvas.drawCircle(center, 9.5, _fill(_ArtColors.yellow));
      canvas.drawCircle(center, 5, _fill(_ArtColors.paper));
    }

    // Решётка и номер
    canvas.drawRRect(_rrect(-19, 0, 38, 11, 5.5), ink);
    canvas.drawRRect(_rrect(-15, 18, 30, 9, 3), _fill(_ArtColors.paper));
  }
}

// Экзаменационный лист с верными ответами
class _AnswerSheetPainter extends _ExamArtPainter {
  const _AnswerSheetPainter() : super(tilt: 7);

  @override
  void paintArt(Canvas canvas) {
    canvas.drawRRect(_rrect(-42, -51, 76, 96, 10), _fill(_ArtColors.paper));
    canvas.drawRRect(_rrect(-31, -40, 40, 6, 3), _fill(_ArtColors.ink));

    const widths = [32.0, 24.0, 28.0];
    for (var i = 0; i < widths.length; i++) {
      final y = -20.0 + i * 17;
      canvas.drawCircle(Offset(-25, y), 6.5, _fill(_ArtColors.green));
      _drawCheck(canvas, Offset(-25, y), 3, 1.8);
      canvas.drawRRect(
        _rrect(-13, y - 2.5, widths[i], 5, 2.5),
        _fill(_ArtColors.mist),
      );
    }

    const seal = Offset(28, 32);
    _drawGlow(canvas, seal, 34, _ArtColors.green, alpha: 0.55);
    canvas.drawCircle(seal, 20, _fill(_ArtColors.green));
    _drawCheck(canvas, seal, 9, 4.5);
  }
}
