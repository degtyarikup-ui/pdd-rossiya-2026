import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/presentation/widgets/cone_mascot_art.dart';

/// A dimensional vector mascot conducting a continuously orbiting loader.
///
/// The master drawing lives in assets/mascot/cone.svg. Its curves and gradients
/// are compiled into Dart so this widget needs no runtime parser, raster frames,
/// additional assets or animation package. Supply an already localized label
/// when this widget should announce loading to a screen reader.
class ConeMascotLoader extends StatefulWidget {
  const ConeMascotLoader({
    super.key,
    this.size = 144,
    this.activityColor = AppColors.accent,
    this.semanticsLabel,
    this.liveRegion = false,
  }) : assert(size > 0 && size < double.infinity);

  final double size;

  /// The orbit color can contrast with the containing surface, for example
  /// white on a blue splash background. The mascot keeps its own material colors.
  final Color activityColor;
  final String? semanticsLabel;
  final bool liveRegion;

  @override
  State<ConeMascotLoader> createState() => _ConeMascotLoaderState();
}

class _ConeMascotLoaderState extends State<ConeMascotLoader>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _animation;
  AppLifecycleState? _lifecycle;
  bool _reducedMotion = false;
  bool _tickerEnabled = true;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncAnimation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _syncAnimation();
  }

  void _syncAnimation() {
    final active =
        !_reducedMotion &&
        _tickerEnabled &&
        (_lifecycle == null || _lifecycle == AppLifecycleState.resumed);
    if (active) {
      if (!_animation.isAnimating) _animation.repeat();
    } else {
      _animation.stop(canceled: false);
      if (_reducedMotion) _animation.value = 0;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget result = RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: _ConeMascotPainter(_animation, widget.activityColor),
        ),
      ),
    );
    final label = widget.semanticsLabel;
    if (label != null && label.isNotEmpty) {
      result = Semantics(
        container: true,
        label: label,
        liveRegion: widget.liveRegion,
        child: ExcludeSemantics(child: result),
      );
    }
    return result;
  }
}

class _ConeMascotPainter extends CustomPainter {
  _ConeMascotPainter(this.animation, this.activityColor)
    : _trackPaint = (Paint()
        ..color = activityColor.withValues(alpha: .16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5),
      _arcPaints = List<Paint>.generate(
        _arcSegments,
        (index) => Paint()
          ..color = activityColor.withValues(
            alpha: .12 + .88 * index / (_arcSegments - 1),
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.butt,
        growable: false,
      ),
      _beadPaint = (Paint()
        ..shader = ui.Gradient.radial(
          const Offset(-2.3, -2.4),
          10,
          [
            Color.lerp(activityColor, Colors.white, .6)!,
            activityColor,
            Color.lerp(activityColor, Colors.black, .16)!,
          ],
          const [0, .48, 1],
        )),
      super(repaint: animation);

  final Animation<double> animation;
  final Color activityColor;
  final Paint _trackPaint;
  final List<Paint> _arcPaints;
  final Paint _beadPaint;

  static const _roadBounds = Rect.fromLTRB(59, 366, 421, 444);
  static const _arcSegments = 24;
  static const _arcSweep = 70 * math.pi / 180;

  // phase, vertical translation, horizontal/vertical scale, rotation in degrees.
  // Two short hops are separated by settled poses; the orbit never pauses.
  static const _poses = <(double, double, double, double, double)>[
    (0, 0, 1, 1, 0),
    (.055, 0, 1.025, .975, -1.6),
    (.11, -18, .99, 1.025, -2.6),
    (.175, -20, 1, 1, 1),
    (.255, 0, 1.03, .97, 2),
    (.32, 0, 1, 1, 0),
    (.48, 0, 1, 1, 0),
    (.53, 0, 1.02, .98, 1.2),
    (.59, -11, .99, 1.02, 2.3),
    (.65, -13, 1, 1, -1),
    (.735, 0, 1.025, .975, -1.6),
    (.79, 0, 1, 1, 0),
    (1, 0, 1, 1, 0),
  ];

  static double _smooth(double value) {
    final t = value.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  static (double, double, double, double) _pose(double phase) {
    for (var index = 1; index < _poses.length; index++) {
      final next = _poses[index];
      if (phase > next.$1) continue;
      final previous = _poses[index - 1];
      final t = _smooth((phase - previous.$1) / (next.$1 - previous.$1));
      return (
        previous.$2 + (next.$2 - previous.$2) * t,
        previous.$3 + (next.$3 - previous.$3) * t,
        previous.$4 + (next.$4 - previous.$4) * t,
        previous.$5 + (next.$5 - previous.$5) * t,
      );
    }
    return (0, 1, 1, 0);
  }

  /// A quick closure, tiny hold, and slightly slower reopening.
  static double _closure(double seconds) {
    const center = 2.65;
    const close = .075;
    const hold = .025;
    const open = .115;
    if (seconds < center - close || seconds > center + hold + open) return 0;
    if (seconds < center) return _smooth((seconds - center + close) / close);
    if (seconds < center + hold) return 1;
    return 1 - _smooth((seconds - center - hold) / open);
  }

  static void _drawEye(
    Canvas canvas,
    Offset origin,
    double closure,
    Offset pupilOffset,
    void Function(Canvas) drawEye,
    void Function(Canvas) drawPupil,
  ) {
    if (closure >= .985) return;
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(1, 1 - closure);
    canvas.translate(-origin.dx, -origin.dy);
    drawEye(canvas);
    canvas.translate(pupilOffset.dx, pupilOffset.dy);
    drawPupil(canvas);
    canvas.restore();
  }

  void _drawRoad(Canvas canvas, double head, {required bool front}) {
    canvas.drawArc(
      _roadBounds,
      front ? 0 : math.pi,
      math.pi,
      false,
      _trackPaint,
    );
    const step = _arcSweep / _arcSegments;
    for (var index = 0; index < _arcSegments; index++) {
      final start = head - _arcSweep + index * step;
      if ((math.sin(start + step / 2) >= 0) != front) continue;
      // Tiny overlap closes antialias seams without creating round-cap knots.
      canvas.drawArc(_roadBounds, start, step + .003, false, _arcPaints[index]);
    }
    // Perspective and depth order make these read as a circulating loader.
    for (var index = 2; index >= 0; index--) {
      final angle = head - index * .28;
      final depth = math.sin(angle);
      if ((depth >= 0) != front) continue;
      final radius = switch (index) {
        0 => 7.0,
        1 => 5.5,
        _ => 4.5,
      };
      final beadScale = radius / 7 * (.82 + .18 * depth);
      canvas.save();
      canvas.translate(240 + 181 * math.cos(angle), 405 + 39 * depth);
      canvas.scale(beadScale);
      canvas.drawCircle(Offset.zero, 7, _beadPaint);
      canvas.restore();
    }
  }

  static void _drawGlove(
    Canvas canvas,
    Offset pivot,
    double degrees,
    void Function(Canvas) draw,
  ) {
    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(degrees * math.pi / 180);
    canvas.translate(-pivot.dx, -pivot.dy);
    draw(canvas);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 480;
    final phase = animation.value;
    final pose = _pose(phase);
    final delayedPose = _pose((phase - .022) % 1);
    final head = phase * math.pi * 4;
    canvas.save();
    canvas.translate(
      (size.width - 480 * scale) / 2,
      (size.height - 480 * scale) / 2,
    );
    canvas.scale(scale);

    _drawRoad(canvas, head, front: false);
    canvas.save();
    canvas.translate(240, 414);
    final shadowScale = 1 + pose.$1 * .004;
    canvas.scale(shadowScale);
    canvas.translate(-240, -414);
    ConeMascotArt.drawGroundShadow(canvas);
    canvas.restore();

    // A shared transform keeps every facial feature attached to the volume.
    canvas.save();
    canvas.translate(240, 402 + pose.$1);
    canvas.rotate(pose.$4 * math.pi / 180);
    canvas.scale(pose.$2, pose.$3);
    canvas.translate(-240, -402);
    ConeMascotArt.drawRearArmLeft(canvas);
    ConeMascotArt.drawRearArmRight(canvas);
    ConeMascotArt.drawBody(canvas);
    ConeMascotArt.drawFace(canvas);

    final blink = _closure(phase * 3.2);
    final pupilOffset = Offset(3 * math.cos(head), 1.1 * math.sin(head));
    _drawEye(
      canvas,
      const Offset(211, 224),
      blink,
      pupilOffset,
      ConeMascotArt.drawEyeLeft,
      ConeMascotArt.drawPupilLeft,
    );
    _drawEye(
      canvas,
      const Offset(273, 222),
      blink,
      pupilOffset,
      ConeMascotArt.drawEyeRight,
      ConeMascotArt.drawPupilRight,
    );
    final lid = _smooth((blink - .5) * 2);
    if (lid > 0) {
      ConeMascotArt.drawLidLeft(canvas, lid);
      ConeMascotArt.drawLidRight(canvas, lid);
    }

    final gesture =
        -delayedPose.$1 / 20 * 7 * math.sin((phase - .022) * math.pi * 4);
    _drawGlove(
      canvas,
      const Offset(151, 294),
      gesture,
      ConeMascotArt.drawGloveLeft,
    );
    _drawGlove(
      canvas,
      const Offset(329, 294),
      -gesture,
      ConeMascotArt.drawGloveRight,
    );
    canvas.restore();

    _drawRoad(canvas, head, front: true);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ConeMascotPainter oldDelegate) =>
      oldDelegate.animation != animation ||
      oldDelegate.activityColor != activityColor;
}
