import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Shared timing for the premium flow. Entry runs once; controls never wait
/// for an animation before carrying out their existing action.
abstract final class PremiumMotion {
  static const entrance = Duration(milliseconds: 680);
  static const statistics = Duration(milliseconds: 1100);
  static const carArrival = Duration(milliseconds: 760);
  static const press = Duration(milliseconds: 90);
  static const release = Duration(milliseconds: 180);
  static const sheetOpen = Duration(milliseconds: 320);
  static const sheetClose = Duration(milliseconds: 220);
}

/// A composited fade and a small, fixed-distance rise. Layout and the child
/// stay unchanged during the sequence, including with large accessibility text.
class PremiumReveal extends StatelessWidget {
  const PremiumReveal({
    super.key,
    required this.progress,
    required this.begin,
    required this.end,
    required this.child,
    this.distance = 12,
  });

  final Animation<double> progress;
  final double begin;
  final double end;
  final double distance;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reveal = progress.drive(
      CurveTween(curve: Interval(begin, end, curve: Curves.easeOutCubic)),
    );
    return AnimatedBuilder(
      animation: reveal,
      child: RepaintBoundary(child: child),
      builder: (context, child) => IgnorePointer(
        ignoring: reveal.value < .05,
        child: FadeTransition(
          opacity: reveal,
          child: Transform.translate(
            offset: Offset(0, distance * (1 - reveal.value)),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Adds a restrained press response to the native button/InkWell underneath.
/// The Listener observes pointers without competing with taps, scrolling,
/// keyboard focus, semantics or the original payment callbacks.
class PremiumPressFeedback extends StatefulWidget {
  const PremiumPressFeedback({
    super.key,
    required this.child,
    this.enabled = true,
    this.pressedScale = .98,
  });

  final Widget child;
  final bool enabled;
  final double pressedScale;

  @override
  State<PremiumPressFeedback> createState() => _PremiumPressFeedbackState();
}

class _PremiumPressFeedbackState extends State<PremiumPressFeedback> {
  int? _pointer;
  Offset? _origin;

  @override
  void didUpdateWidget(PremiumPressFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _pointer = null;
      _origin = null;
    }
  }

  void _release(PointerEvent event) {
    if (_pointer == event.pointer) {
      setState(() {
        _pointer = null;
        _origin = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final pressed = _pointer != null && widget.enabled && !reducedMotion;
    return Listener(
      onPointerDown: (event) {
        if (widget.enabled &&
            !reducedMotion &&
            event.buttons == kPrimaryButton &&
            _pointer == null) {
          setState(() {
            _pointer = event.pointer;
            _origin = event.position;
          });
        }
      },
      onPointerMove: (event) {
        if (_pointer == event.pointer &&
            (event.position - _origin!).distance > kTouchSlop) {
          _release(event);
        }
      },
      onPointerUp: _release,
      onPointerCancel: _release,
      child: AnimatedScale(
        scale: pressed ? widget.pressedScale : 1,
        duration: reducedMotion
            ? Duration.zero
            : pressed
            ? PremiumMotion.press
            : PremiumMotion.release,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
