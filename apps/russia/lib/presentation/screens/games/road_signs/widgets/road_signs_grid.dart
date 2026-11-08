import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/data/models/road_signs_model.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Four equal targets. Feedback never changes their size or position: the
/// motion (arrival, press, the right sign's nod, the wrong one's shake) is
/// painted inside each fixed cell.
///
/// A new question needs a new key, so the cells arrive again one by one.
class RoadSignsGrid extends StatelessWidget {
  final List<SignItem> options;
  final ValueChanged<int> onSelectOption;
  final bool isEnabled;
  final int? selectedIndex;
  final int? correctIndex;
  final bool? isCorrect;

  const RoadSignsGrid({
    super.key,
    required this.options,
    required this.onSelectOption,
    this.isEnabled = true,
    this.selectedIndex,
    this.correctIndex,
    this.isCorrect,
  }) : assert(options.length == 4, 'RoadSignsGrid requires exactly 4 options');

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppDimensions.spacingM;
        final side = math.max(
          0.0,
          (math.min(constraints.maxWidth, constraints.maxHeight) - gap) / 2,
        );
        return Center(
          child: SizedBox.square(
            dimension: side * 2 + gap,
            child: Column(
              children: [
                for (var row = 0; row < 2; row++) ...[
                  if (row > 0) const SizedBox(height: gap),
                  Row(
                    children: [
                      for (var column = 0; column < 2; column++) ...[
                        if (column > 0) const SizedBox(width: gap),
                        _tile(row * 2 + column, side),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tile(int index, double side) {
    final answered = selectedIndex != null;
    final selected = selectedIndex == index;
    final correct = answered && correctIndex == index;
    final wrong = selected && isCorrect == false;
    final verdict = correct
        ? _Verdict.right
        : wrong
        ? _Verdict.wrong
        : answered
        ? _Verdict.dimmed
        : _Verdict.none;
    return Semantics(
      key: ValueKey('road-sign-option-$index'),
      button: true,
      onTap: isEnabled ? () => onSelectOption(index) : null,
      enabled: isEnabled,
      selected: selected,
      // Describe the choice without giving away its name before answering.
      label: appL10n.roadSignsOption(index + 1),
      value: correct
          ? appL10n.gameCorrectAnswer
          : wrong
          ? appL10n.gameAnswerWrong
          : null,
      child: SizedBox.square(
        dimension: side,
        child: _SignTile(
          index: index,
          side: side,
          asset: options[index].assetPath,
          verdict: verdict,
          chosen: selected,
          onTap: isEnabled ? () => onSelectOption(index) : null,
        ),
      ),
    );
  }
}

enum _Verdict { none, right, wrong, dimmed }

class _SignTile extends StatefulWidget {
  const _SignTile({
    required this.index,
    required this.side,
    required this.asset,
    required this.verdict,
    required this.chosen,
    required this.onTap,
  });

  final int index;
  final double side;
  final String asset;
  final _Verdict verdict;

  /// The player's own choice: only it nods or shakes.
  final bool chosen;
  final VoidCallback? onTap;

  @override
  State<_SignTile> createState() => _SignTileState();
}

class _SignTileState extends State<_SignTile> with TickerProviderStateMixin {
  // The four cells arrive 45 ms apart within one shared span.
  static const _stagger = 45;
  static const _arrival = 340;

  late final AnimationController _arrive = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _arrival + 3 * _stagger),
  );
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    reverseDuration: const Duration(milliseconds: 260),
  );
  late final AnimationController _verdict = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );
  late final Animation<double> _arrivalCurve = CurvedAnimation(
    parent: _arrive,
    curve: Interval(
      widget.index * _stagger / (_arrival + 3 * _stagger),
      (widget.index * _stagger + _arrival) / (_arrival + 3 * _stagger),
      curve: Curves.easeOutCubic,
    ),
  );
  bool _started = false;

  bool get _reduced => MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (_reduced) {
      _arrive.value = 1;
    } else {
      _arrive.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _SignTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.verdict == widget.verdict) return;
    if (widget.verdict == _Verdict.right || widget.verdict == _Verdict.wrong) {
      _arrive.value = 1;
      if (_reduced) {
        _verdict.value = 1;
      } else {
        _verdict.forward(from: 0);
      }
    } else if (widget.verdict == _Verdict.none) {
      _verdict.value = 0;
    }
  }

  @override
  void dispose() {
    _arrive.dispose();
    _press.dispose();
    _verdict.dispose();
    super.dispose();
  }

  void _highlight(bool down) {
    if (_reduced || widget.onTap == null && down) return;
    down ? _press.forward() : _press.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final verdict = widget.verdict;
    final right = verdict == _Verdict.right;
    final wrong = verdict == _Verdict.wrong;
    final tint = right ? colors.green : colors.red;
    final surface = right
        ? colors.greenLight
        : wrong
        ? colors.redLight
        : colors.cardBackground;
    final radius = BorderRadius.circular(AppDimensions.radiusExtraLarge - 4);
    final fade = _reduced ? Duration.zero : const Duration(milliseconds: 200);
    final badge = math.min(28.0, widget.side * 0.19);

    return AnimatedBuilder(
      animation: Listenable.merge([_arrivalCurve, _press, _verdict]),
      builder: (context, child) {
        final arrival = _arrivalCurve.value;
        final press = Curves.easeOut.transform(_press.value);
        final t = _verdict.value;
        // The chosen right sign nods once; the chosen wrong one shakes, settling.
        final nod = right && widget.chosen ? 0.05 * math.sin(math.pi * t) : 0.0;
        final shake = wrong && widget.chosen
            ? math.sin(t * math.pi * 6) *
                  widget.side *
                  0.045 *
                  math.pow(1 - t, 2)
            : 0.0;
        return Opacity(
          opacity: arrival,
          child: Transform.translate(
            offset: Offset(shake, 10 * (1 - arrival)),
            child: Transform.scale(
              scale: (0.92 + 0.08 * arrival) * (1 - 0.05 * press) + nod,
              child: child,
            ),
          ),
        );
      },
      child: AnimatedOpacity(
        opacity: verdict == _Verdict.dimmed ? 0.38 : 1,
        duration: fade,
        child: AnimatedScale(
          scale: verdict == _Verdict.dimmed ? 0.96 : 1,
          duration: fade,
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: fade,
            curve: Curves.easeOut,
            decoration: BoxDecoration(color: surface, borderRadius: radius),
            foregroundDecoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: right || wrong ? tint : Colors.transparent,
                width: 2,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              borderRadius: radius,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.onTap,
                onHighlightChanged: _highlight,
                excludeFromSemantics: true,
                splashFactory: NoSplash.splashFactory,
                overlayColor: WidgetStateProperty.resolveWith((states) {
                  if (widget.onTap != null &&
                      (states.contains(WidgetState.focused) ||
                          states.contains(WidgetState.hovered))) {
                    return colors.accent.withValues(alpha: 0.08);
                  }
                  return Colors.transparent;
                }),
                child: ExcludeSemantics(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Padding(
                          padding: EdgeInsets.all(widget.side * 0.19),
                          child: SvgPicture.asset(
                            widget.asset,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      if (right || wrong)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: _VerdictBadge(
                            animation: _verdict,
                            size: badge,
                            color: tint,
                            icon: right
                                ? Icons.check_rounded
                                : Icons.close_rounded,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The corner mark pops in with a small overshoot, never covering the sign.
class _VerdictBadge extends StatelessWidget {
  const _VerdictBadge({
    required this.animation,
    required this.size,
    required this.color,
    required this.icon,
  });

  final Animation<double> animation;
  final double size;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = (animation.value / 0.55).clamp(0.0, 1.0);
        return Transform.scale(
          scale: Curves.easeOutBack.transform(t),
          child: child,
        );
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, size: size * 0.68, color: Colors.white),
      ),
    );
  }
}
