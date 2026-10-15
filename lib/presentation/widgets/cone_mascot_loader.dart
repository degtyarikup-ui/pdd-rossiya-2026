import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdd_app/presentation/widgets/cone_mascot_art.dart';

/// A native vector loading mascot, with one quiet, seamless six-second loop.
///
/// The master drawing lives in assets/mascot/cone.svg. Its curves and gradients
/// are compiled into Dart so this widget needs no runtime parser, raster frames,
/// additional assets or animation package. Supply an already localized label
/// when this widget should announce loading to a screen reader.
class ConeMascotLoader extends StatefulWidget {
  const ConeMascotLoader({
    super.key,
    this.size = 144,
    this.semanticsLabel,
    this.liveRegion = false,
  }) : assert(size > 0 && size < double.infinity);

  final double size;
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
      duration: const Duration(seconds: 6),
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
        child: CustomPaint(painter: _ConeMascotPainter(_animation)),
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
  _ConeMascotPainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  static double _smooth(double value) {
    final t = value.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  /// The short closure has a soft ease in, a tiny hold and slower reopening.
  static double _closure(
    double seconds,
    double center, {
    double close = .09,
    double hold = .025,
    double open = .13,
  }) {
    final start = center - close;
    if (seconds < start || seconds > center + hold + open) return 0;
    if (seconds < center) return _smooth((seconds - start) / close);
    if (seconds < center + hold) return 1;
    return 1 - _smooth((seconds - center - hold) / open);
  }

  static void _drawEye(
    Canvas canvas,
    Offset origin,
    double closure,
    void Function(Canvas) draw,
  ) {
    if (closure >= .985) return;
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(1, 1 - closure);
    canvas.translate(-origin.dx, -origin.dy);
    draw(canvas);
    canvas.restore();
  }

  static double _thumbDegrees(double phase) {
    if (phase < .15 || phase > .44) return 0;
    if (phase < .25) return -7 * _smooth((phase - .15) / .1);
    if (phase < .31) return -7 + 6 * _smooth((phase - .25) / .06);
    if (phase < .36) return -1 - 6 * _smooth((phase - .31) / .05);
    return -7 + 7 * _smooth((phase - .36) / .08);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 480;
    final phase = animation.value;
    final seconds = phase * 6;
    final breath = math.sin(phase * math.pi * 2);
    canvas.save();
    canvas.translate(
      (size.width - 480 * scale) / 2,
      (size.height - 480 * scale) / 2,
    );
    canvas.scale(scale);

    // One shared transform keeps the face, glove and cone firmly attached.
    canvas.translate(240, 410 - 4 * breath * breath);
    canvas.rotate(.7 * math.pi / 180 * breath);
    canvas.scale(1 - .002 * breath, 1 + .004 * breath);
    canvas.translate(-240, -410);

    ConeMascotArt.drawRearArm(canvas);
    ConeMascotArt.drawBody(canvas);
    ConeMascotArt.drawFace(canvas);

    final blink = _closure(seconds, 2.65);
    final wink = _closure(seconds, 4.5, close: .12, hold: .09, open: .19);
    final rightClosure = math.max(blink, wink);
    _drawEye(canvas, const Offset(201, 232), blink, ConeMascotArt.drawEyeLeft);
    _drawEye(
      canvas,
      const Offset(283, 218),
      rightClosure,
      ConeMascotArt.drawEyeRight,
    );
    final leftLid = _smooth((blink - .5) * 2);
    final rightLid = _smooth((rightClosure - .5) * 2);
    if (leftLid > 0) ConeMascotArt.drawLidLeft(canvas, leftLid);
    if (rightLid > 0) ConeMascotArt.drawLidRight(canvas, rightLid);

    // Two reassuring little nods, with smooth zero-velocity endpoints.
    canvas.save();
    canvas.translate(124, 334);
    canvas.rotate(_thumbDegrees(phase) * math.pi / 180);
    canvas.translate(-124, -334);
    ConeMascotArt.drawThumb(canvas);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ConeMascotPainter oldDelegate) =>
      oldDelegate.animation != animation;
}
