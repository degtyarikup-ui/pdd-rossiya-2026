import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:pdd_app/core/constants/app_colors.dart';

/// A white vector flame: its base stays planted while three tips and the inner
/// tongue move independently. Geometry matches Godot's burning_flame.gd.
class BurningFlame extends StatefulWidget {
  const BurningFlame({super.key, required this.size});
  final double size;

  @override
  State<BurningFlame> createState() => _BurningFlameState();
}

class _BurningFlameState extends State<BurningFlame>
    with SingleTickerProviderStateMixin {
  late final _fire = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _fire.stop();
    } else if (!_fire.isAnimating) {
      _fire.repeat();
    }
  }

  @override
  void dispose() {
    _fire.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(painter: _FlamePainter(_fire)),
    ),
  );
}

class _FlamePainter extends CustomPainter {
  _FlamePainter(this.fire) : super(repaint: fire);
  final Animation<double> fire;

  @override
  void paint(Canvas canvas, Size size) {
    final t = fire.value;
    final a = t * math.pi * 2;
    final tip = 4 * math.sin(a) + math.sin(a * 3);
    final left = 2 * math.sin(a * 2 + .8);
    final right = 2 * math.sin(a * 3 + 1.3);
    final inner = 2.5 * math.sin(a * 2 - .7);
    final scale = math.min(size.width / 100, size.height / 120);
    canvas.save();
    canvas.translate(
      (size.width - 100 * scale) / 2,
      (size.height - 120 * scale) / 2,
    );
    canvas.scale(scale);
    final body = Path()
      ..moveTo(50, 112)
      ..cubicTo(26, 112, 14, 95, 14, 77)
      ..cubicTo(14, 64, 20 + left, 54, 26 + left, 47)
      ..cubicTo(26 + left, 60, 31, 67, 37, 68)
      ..cubicTo(30, 45, 43 + tip, 25, 60 + tip, 9 + math.sin(a * 2) * 2)
      ..cubicTo(56 + tip, 32, 70, 38, 76, 52)
      ..cubicTo(79, 46, 79 + right, 42, 78 + right, 37)
      ..cubicTo(90 + right, 53, 94, 66, 92, 80)
      ..cubicTo(90, 100, 73, 112, 50, 112)
      ..close();
    canvas.drawPath(body, Paint()..color = AppColors.white);

    final heart = Path()
      ..moveTo(51, 104)
      ..cubicTo(35, 104, 32, 91, 36, 82)
      ..cubicTo(38, 75, 43 + inner, 69, 48 + inner, 61)
      ..cubicTo(47 + inner, 73, 55, 77, 57, 82)
      ..cubicTo(58, 78, 59 + inner, 76, 59 + inner, 74)
      ..cubicTo(66, 83, 70, 92, 63, 100)
      ..cubicTo(60, 103, 56, 104, 51, 104)
      ..close();
    canvas.drawPath(
      heart,
      Paint()..color = Color.lerp(AppColors.gold, AppColors.white, .10)!,
    );

    for (var i = 0; i < 3; i++) {
      final progress = (t + i / 3) % 1;
      final fade = math.pow(math.sin(progress * math.pi), 2).toDouble();
      final x = [23.0, 79.0, 43.0][i] + math.sin(a + i * 2) * 2.5;
      final y = [45.0, 32.0, 21.0][i] - progress * 22;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(math.sin(a + i) * .3);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: 2.8 * fade,
          height: 5.5 * fade,
        ),
        Paint()..color = AppColors.white.withValues(alpha: .75 * fade),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FlamePainter oldDelegate) =>
      fire != oldDelegate.fire;
}
