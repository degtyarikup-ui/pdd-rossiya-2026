import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';

/// Общий завершающий экран: итог игры, билета, темы, экзамена.
///
/// Формат пришёл из игр (`game_godot/scripts/mini_game_results.gd`): цветной
/// фон во весь экран, бледные лучи от плашки итога, эмблема со свечением,
/// плашка со счётом от нуля, метрики под ней, закреплённые внизу действия и
/// крестик. Успех — синий фон ([success]), неудача — красный ([failure]).
class ResultStage extends StatefulWidget {
  const ResultStage({
    super.key,
    required this.background,
    required this.title,
    required this.emblem,
    required this.badge,
    required this.actions,
    required this.onClose,
    required this.closeTooltip,
    this.caption,
    this.captionStrong = false,
    this.stats = const [],
    this.leading = const [],
    this.spinRays = true,
    this.rays = true,
  });

  static const success = Color(0xFF0574F8); // AppColors.light.accent
  static const failure = Color(0xFFE5432B);

  final Color background;
  final String title;
  final Widget emblem;
  final ResultBadge badge;

  /// Строка под плашкой: рекорд, лучший счёт, вердикт.
  final String? caption;

  /// Белым и жирнее — для новости («Новый рекорд»), а не для пояснения.
  final bool captionStrong;

  /// Метрики под плашкой; числа считаются от нуля вместе с плашкой.
  final List<ResultStat> stats;

  /// Кнопки внизу, сверху вниз: вторичные, затем основная.
  final List<Widget> actions;

  final VoidCallback onClose;
  final String closeTooltip;

  /// Иконки слева от заголовка (поделиться, пояснение); крестик всегда справа.
  final List<ResultHeaderButton> leading;

  /// Игры крутят лучи без конца (оборот за минуту). Итог учёбы лишь доворачивает
  /// их при появлении: экран остаётся спокойным и не держит анимацию вечно.
  final bool spinRays;

  /// Лучи — знак успеха: на итоге неудачи их нет.
  final bool rays;

  @override
  State<ResultStage> createState() => _ResultStageState();
}

class _ResultStageState extends State<ResultStage>
    with TickerProviderStateMixin {
  late final AnimationController _count = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );
  late final AnimationController _arrival = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 820),
  );
  late final AnimationController _rays = AnimationController(
    vsync: this,
    duration: widget.spinRays
        ? const Duration(minutes: 1)
        : const Duration(milliseconds: 2400),
  );
  final _pill = GlobalKey();
  final _stack = GlobalKey();
  final _raysCentre = ValueNotifier<Offset?>(null);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _count.value = 1;
      _arrival.value = 1;
      _rays.stop();
    } else if (!_count.isAnimating && _count.value == 0) {
      _count.forward();
      _arrival.forward();
      if (widget.rays) widget.spinRays ? _rays.repeat() : _rays.forward();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _locateRays());
  }

  @override
  void dispose() {
    _count.dispose();
    _arrival.dispose();
    _rays.dispose();
    _raysCentre.dispose();
    super.dispose();
  }

  /// Лучи центрируются по реальной плашке, в том числе при прокрутке.
  void _locateRays() {
    if (!mounted) return;
    final pill = _pill.currentContext?.findRenderObject() as RenderBox?;
    final stack = _stack.currentContext?.findRenderObject() as RenderBox?;
    if (pill == null || stack == null || !pill.attached) return;
    _raysCentre.value = stack.globalToLocal(
      pill.localToGlobal(pill.size.center(Offset.zero)),
    );
  }

  double get _raysAngle => widget.spinRays
      ? _rays.value * 2 * pi
      : Curves.easeOutCubic.transform(_rays.value) * pi / 9;

  @override
  Widget build(BuildContext context) {
    final dim = Colors.white.withValues(alpha: 0.7);
    final height = MediaQuery.sizeOf(context).height;
    final sideWidth = 48.0 * max(1, widget.leading.length);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        color: widget.background,
        child: Stack(
          key: _stack,
          children: [
            if (widget.rays)
              Positioned.fill(
                child: IgnorePointer(
                  child: ValueListenableBuilder<Offset?>(
                    valueListenable: _raysCentre,
                    builder: (context, centre, _) => centre == null
                        ? const SizedBox.shrink()
                        : AnimatedBuilder(
                            animation: _rays,
                            builder: (context, _) => CustomPaint(
                              painter: ResultRaysPainter(centre, _raysAngle),
                            ),
                          ),
                  ),
                ),
              ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: sideWidth,
                              child: Row(children: widget.leading),
                            ),
                            Expanded(
                              child: Text(
                                widget.title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontFamily: 'Onest',
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: sideWidth,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: ResultHeaderButton(
                                  icon: Icons.close_rounded,
                                  tooltip: widget.closeTooltip,
                                  onPressed: widget.onClose,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (_) {
                              _locateRays();
                              return false;
                            },
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: (height * 0.36).clamp(150.0, 300.0),
                                    child: AnimatedBuilder(
                                      animation: _arrival,
                                      builder: (context, child) {
                                        final t = Curves.easeOutCubic.transform(
                                          _arrival.value,
                                        );
                                        return Opacity(
                                          opacity: t,
                                          child: Transform.translate(
                                            offset: Offset(0, 16 * (1 - t)),
                                            child: child,
                                          ),
                                        );
                                      },
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          const Positioned.fill(
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                gradient: RadialGradient(
                                                  colors: [
                                                    Color(0x40FFFFFF),
                                                    Color(0x00FFFFFF),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          widget.emblem,
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  AnimatedBuilder(
                                    animation: _count,
                                    builder: (context, _) => KeyedSubtree(
                                      key: _pill,
                                      child: widget.badge._build(_count.value),
                                    ),
                                  ),
                                  if (widget.caption != null) ...[
                                    const SizedBox(height: 16),
                                    Text(
                                      widget.caption!,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: widget.captionStrong
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                        color: widget.captionStrong
                                            ? Colors.white
                                            : dim,
                                      ),
                                    ),
                                  ],
                                  if (widget.stats.isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    AnimatedBuilder(
                                      animation: _count,
                                      builder: (context, _) => _StatsGrid(
                                        stats: widget.stats,
                                        progress: _count.value,
                                        labelColor: dim,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (final (i, action) in widget.actions.indexed) ...[
                          if (i > 0) const SizedBox(height: 12),
                          action,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Плашка итога: число, которое считается от нуля, и иконка перед ним (у игр —
/// звезда); [suffix] после числа не анимируется («/20»).
class ResultBadge {
  const ResultBadge({
    required this.value,
    required this.color,
    required this.foreground,
    required this.semanticsLabel,
    this.suffix = '',
    this.icon,
  });

  final int value;
  final String suffix;
  final IconData? icon;
  final Color color;
  final Color foreground;
  final String semanticsLabel;

  Widget _build(double progress) {
    final style = _style.copyWith(color: foreground);
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(40),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 32, color: foreground),
              const SizedBox(width: 10),
            ],
            // Ширина под все цифры заранее: плашка не дёргается.
            Stack(
              alignment: Alignment.centerLeft,
              children: [
                Opacity(
                  opacity: 0,
                  child: Text('8' * '$value'.length + suffix, style: style),
                ),
                Text('${(value * progress).round()}$suffix', style: style),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static const _style = TextStyle(
    fontFamily: 'Onest',
    fontSize: 36,
    fontWeight: FontWeight.w800,
    height: 1.1,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

class ResultStat {
  const ResultStat(this.label, this.value, {this.color, this.counted = true});

  final String label;
  final String value;
  final Color? color;

  /// Первое число в [value] считается от нуля; время («12:05») — нет.
  final bool counted;
}

/// До трёх метрик в строку; четыре — сеткой два на два.
class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.stats,
    required this.progress,
    required this.labelColor,
  });

  final List<ResultStat> stats;
  final double progress;
  final Color labelColor;

  String _counted(ResultStat stat) {
    if (!stat.counted) return stat.value;
    final match = RegExp(r'^(\D*)(\d+)(.*)$').firstMatch(stat.value);
    if (match == null) return stat.value;
    final number = int.parse(match.group(2)!);
    return '${match.group(1)}${(number * progress).round()}${match.group(3)}';
  }

  @override
  Widget build(BuildContext context) {
    final perRow = stats.length == 4 ? 2 : 3;
    return Column(
      children: [
        for (var start = 0; start < stats.length; start += perRow) ...[
          if (start > 0) const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final stat in stats.skip(start).take(perRow))
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        _counted(stat),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Onest',
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: stat.color ?? Colors.white,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        stat.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: labelColor,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Белая иконка-кнопка в шапке.
class ResultHeaderButton extends StatelessWidget {
  const ResultHeaderButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 48,
      child: IconButton(
        tooltip: tooltip,
        onPressed: () {
          HapticFeedbackHelper.tap();
          onPressed();
        },
        icon: Icon(icon, color: Colors.white),
      ),
    );
  }
}

/// Белая основная и полупрозрачная вторичная кнопки; нажатие — 97% за 70 мс.
/// Текст основной — цвета фона экрана ([accent]).
class ResultButton extends StatefulWidget {
  const ResultButton({
    super.key,
    required this.label,
    required this.primary,
    required this.onPressed,
    this.accent = ResultStage.success,
    this.icon,
  });

  final String label;
  final bool primary;
  final VoidCallback onPressed;
  final Color accent;
  final IconData? icon;

  @override
  State<ResultButton> createState() => _ResultButtonState();
}

class _ResultButtonState extends State<ResultButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final foreground = widget.primary ? widget.accent : Colors.white;
    return AnimatedScale(
      scale: _down ? 0.97 : 1,
      duration: Duration(milliseconds: _down ? 70 : 180),
      child: Material(
        color: widget.primary
            ? Colors.white
            : Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onHighlightChanged: (down) => setState(() => _down = down),
          onTap: () {
            HapticFeedbackHelper.tap();
            widget.onPressed();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 20, color: foreground),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      widget.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Эмблема итога учёбы: белый значок с галочкой или крестиком в двух
/// полупрозрачных кольцах — на месте игровой эмблемы.
class ResultVerdictEmblem extends StatelessWidget {
  const ResultVerdictEmblem({super.key, required this.passed, this.size});

  final bool passed;

  /// Диаметр внешнего кольца; без него — по месту, от 120 до 200.
  final double? size;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size =
            this.size ??
            (min(constraints.maxHeight, constraints.maxWidth) * 0.8).clamp(
              120.0,
              200.0,
            );
        Widget ring(double factor, double alpha, {Widget? child}) => Container(
          width: size * factor,
          height: size * factor,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: alpha),
          ),
          child: child,
        );
        return ring(
          1,
          0.12,
          child: ring(
            0.8,
            0.18,
            child: Container(
              width: size * 0.6,
              height: size * 0.6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0x29000000),
                    blurRadius: size * 0.14,
                    offset: Offset(0, size * 0.06),
                  ),
                ],
              ),
              child: Icon(
                passed ? Icons.check_rounded : Icons.close_rounded,
                size: size * 0.36,
                color: passed ? ResultStage.success : ResultStage.failure,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Двенадцать бледных лучей от центра плашки.
class ResultRaysPainter extends CustomPainter {
  ResultRaysPainter(this.centre, this.angle);
  final Offset centre;
  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.longestSide;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: const [Color(0x0CFFFFFF), Color(0x00FFFFFF)],
      ).createShader(Rect.fromCircle(center: centre, radius: radius));
    for (var i = 0; i < 12; i++) {
      final a = angle + i * 2 * pi / 12;
      final path = Path()
        ..moveTo(centre.dx, centre.dy)
        ..lineTo(centre.dx + cos(a) * radius, centre.dy + sin(a) * radius)
        ..lineTo(
          centre.dx + cos(a + 0.19) * radius,
          centre.dy + sin(a + 0.19) * radius,
        )
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(ResultRaysPainter old) =>
      old.centre != centre || old.angle != angle;
}
