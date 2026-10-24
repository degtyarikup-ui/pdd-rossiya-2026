import 'dart:math';
import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Общие элементы мини-игр. Только токены темы, без обводок; лёгкая тень —
/// лишь там, где белая карточка иначе теряется на светлом фоне.

/// Мягкая тень для белых карточек в светлой теме (в тёмной не видна и не нужна).
List<BoxShadow> gameSoftShadow(AppThemeColors colors) => colors.isDark
    ? const []
    : const [
        BoxShadow(
          color: Color(0x14101828),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ];

/// Жизни сердцами: оставшиеся красные, потерянные приглушены.
class GameLives extends StatelessWidget {
  const GameLives({super.key, required this.lives, this.total = 3});

  final int lives;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 3),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 220),
              scale: i < lives ? 1 : 0.85,
              child: Icon(
                i < lives
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: total > 3 ? 15 : 22,
                color: i < lives ? colors.red : colors.secondaryText,
              ),
            ),
          ),
      ],
    );
  }
}

/// Счёт блица: число и множитель серии, если он есть.
class GameScoreLabel extends StatelessWidget {
  const GameScoreLabel({super.key, required this.score, this.streak = 0});

  final int score;
  final int streak;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.star_rounded, size: 22, color: colors.gold),
        const SizedBox(width: 4),
        Text(
          '$score',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: colors.primaryText,
          ),
        ),
        if (streak > 1) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colors.goldLightSurface,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              appL10n.gameCurrentCombo(streak),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: colors.gold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Полоса оставшегося времени: убывает плавно, к концу краснеет.
class GameTimeBar extends StatelessWidget {
  const GameTimeBar({
    super.key,
    required this.secondsLeft,
    required this.totalSeconds,
  });

  final int secondsLeft;
  final int totalSeconds;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final fraction = (secondsLeft / totalSeconds).clamp(0.0, 1.0);
    final urgent = secondsLeft <= 10;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 6,
              color: colors.gray,
              alignment: Alignment.centerLeft,
              child: AnimatedFractionallySizedBox(
                duration: const Duration(milliseconds: 950),
                curve: Curves.linear,
                widthFactor: fraction,
                heightFactor: 1,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  color: urgent ? colors.red : colors.accent,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppDimensions.spacingS),
        SizedBox(
          width: MediaQuery.textScalerOf(context).scale(48),
          child: Text(
            appL10n.gameSecondsLeft(secondsLeft),
            maxLines: 1,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: urgent ? colors.red : colors.secondaryText,
            ),
          ),
        ),
      ],
    );
  }
}

/// Кнопка действия на всю ширину: заливка и цвет текста задаёт состояние.
class GameActionButton extends StatelessWidget {
  const GameActionButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.background,
    required this.foreground,
    this.icon,
    this.iconColor,
    this.height = AppDimensions.answerOptionHeight,
  });

  final String label;
  final VoidCallback? onTap;
  final Color background;
  final Color foreground;
  final IconData? icon;
  final Color? iconColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: iconColor ?? foreground),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Круглая кнопка ответа с подписью: «нет» слева, «да» справа.
class GameRoundButton extends StatefulWidget {
  const GameRoundButton({
    super.key,
    required this.icon,
    required this.color,
    required this.surface,
    required this.onTap,
    this.iconColor,
    this.label,
    this.size = 76,
  });

  final IconData icon;
  final String? label;
  final Color color;
  final Color surface;
  final Color? iconColor;
  final VoidCallback onTap;
  final double size;

  @override
  State<GameRoundButton> createState() => _GameRoundButtonState();
}

class _GameRoundButtonState extends State<GameRoundButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedScale(
          scale: _pressed ? 0.94 : 1,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: Material(
            color: widget.surface,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) => setState(() => _pressed = false),
              onTapCancel: () => setState(() => _pressed = false),
              onTap: widget.onTap,
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: Icon(
                  widget.icon,
                  size: widget.size * 0.46,
                  color: widget.iconColor ?? widget.color,
                ),
              ),
            ),
          ),
        ),
        if (widget.label != null) ...[
          const SizedBox(height: AppDimensions.spacingS),
          Text(
            widget.label!,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: widget.color,
            ),
          ),
        ],
      ],
    );
  }
}

class GameResultStat {
  const GameResultStat(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;
}

/// Итог раунда в общем формате завершающего экрана игр (как
/// `game_godot/scripts/mini_game_results.gd`): синий фон во весь экран,
/// медленные лучи от плашки очков, эмблема игры со свечением, золотая плашка
/// со счётом от нуля, две метрики, закреплённые внизу действия и крестик.
class GameResultOverlay extends StatefulWidget {
  const GameResultOverlay({
    super.key,
    required this.emblem,
    required this.title,
    required this.score,
    required this.bestScore,
    required this.isNewRecord,
    required this.stats,
    required this.onRestart,
    required this.onExit,
    this.mistakesCount = 0,
    this.onMistakes,
  });

  final Widget emblem;
  final String title;
  final int score;

  /// Рекорд до этого раунда — показывается, если новый не поставлен.
  final int bestScore;
  final bool isNewRecord;

  /// Две метрики под очками; числовые значения считаются от нуля вместе с очками.
  final List<GameResultStat> stats;
  final VoidCallback onRestart;
  final VoidCallback onExit;
  final int mistakesCount;
  final VoidCallback? onMistakes;

  @override
  State<GameResultOverlay> createState() => _GameResultOverlayState();
}

class _GameResultOverlayState extends State<GameResultOverlay>
    with TickerProviderStateMixin {
  static const _background = Color(0xFF0574F8); // AppColors.light.accent
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
    duration: const Duration(minutes: 1),
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
      _rays.repeat();
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

  /// Лучи центрируются по реальной плашке очков, в том числе при прокрутке.
  void _locateRays() {
    if (!mounted) return;
    final pill = _pill.currentContext?.findRenderObject() as RenderBox?;
    final stack = _stack.currentContext?.findRenderObject() as RenderBox?;
    if (pill == null || stack == null || !pill.attached) return;
    _raysCentre.value = stack.globalToLocal(
      pill.localToGlobal(pill.size.center(Offset.zero)),
    );
  }

  String _counted(String value, double t) {
    final match = RegExp(r'^(\D*)(\d+)(.*)$').firstMatch(value);
    if (match == null) return value;
    final number = int.parse(match.group(2)!);
    return '${match.group(1)}${(number * t).round()}${match.group(3)}';
  }

  @override
  Widget build(BuildContext context) {
    final gold = AppThemeColors.light.gold;
    final dim = Colors.white.withValues(alpha: 0.65);
    final height = MediaQuery.sizeOf(context).height;
    return Material(
      color: _background,
      child: Stack(
        key: _stack,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder<Offset?>(
                valueListenable: _raysCentre,
                builder: (context, centre, _) => centre == null
                    ? const SizedBox.shrink()
                    : AnimatedBuilder(
                        animation: _rays,
                        builder: (context, _) => CustomPaint(
                          painter: _RaysPainter(centre, _rays.value * 2 * pi),
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
                          const SizedBox(width: 48),
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
                          SizedBox.square(
                            dimension: 48,
                            child: IconButton(
                              tooltip: appL10n.gameExit,
                              onPressed: () {
                                HapticFeedbackHelper.tap();
                                widget.onExit();
                              },
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
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
                                  builder: (context, _) => Semantics(
                                    label:
                                        '${appL10n.gameScore}: ${widget.score}',
                                    child: Container(
                                      key: _pill,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: gold,
                                        borderRadius: BorderRadius.circular(40),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.star_rounded,
                                            size: 32,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 10),
                                          // Ширина под все цифры заранее: плашка не дёргается.
                                          Stack(
                                            alignment: Alignment.centerLeft,
                                            children: [
                                              Opacity(
                                                opacity: 0,
                                                child: Text(
                                                  '8' *
                                                      '${widget.score}'.length,
                                                  style: _scoreStyle,
                                                ),
                                              ),
                                              Text(
                                                '${(widget.score * _count.value).round()}',
                                                style: _scoreStyle,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                if (widget.isNewRecord) ...[
                                  const SizedBox(height: 16),
                                  Text(
                                    appL10n.gameNewRecord,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ] else if (widget.bestScore > 0) ...[
                                  const SizedBox(height: 16),
                                  Text(
                                    appL10n.gameBestScore(widget.bestScore),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: dim,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                AnimatedBuilder(
                                  animation: _count,
                                  builder: (context, _) => Row(
                                    children: [
                                      for (final stat in widget.stats)
                                        Expanded(
                                          child: Column(
                                            children: [
                                              Text(
                                                _counted(
                                                  stat.value,
                                                  _count.value,
                                                ),
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontFamily: 'Onest',
                                                  fontSize: 24,
                                                  fontWeight: FontWeight.w800,
                                                  color: Colors.white,
                                                  fontFeatures: [
                                                    FontFeature.tabularFigures(),
                                                  ],
                                                ),
                                              ),
                                              Text(
                                                stat.label,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                  color: dim,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (widget.mistakesCount > 0 &&
                          widget.onMistakes != null) ...[
                        _ResultButton(
                          label: appL10n.gameRunMistakesButton(
                            widget.mistakesCount,
                          ),
                          icon: Icons.error_outline_rounded,
                          primary: false,
                          onPressed: widget.onMistakes!,
                        ),
                        const SizedBox(height: 12),
                      ],
                      _ResultButton(
                        label: appL10n.gameRestart,
                        primary: true,
                        onPressed: widget.onRestart,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _scoreStyle = TextStyle(
    fontFamily: 'Onest',
    fontSize: 36,
    fontWeight: FontWeight.w800,
    height: 1.1,
    color: Colors.white,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

/// Белая основная и полупрозрачная вторичная кнопки; нажатие — 97% за 70 мс.
class _ResultButton extends StatefulWidget {
  const _ResultButton({
    required this.label,
    required this.primary,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final bool primary;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  State<_ResultButton> createState() => _ResultButtonState();
}

class _ResultButtonState extends State<_ResultButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final foreground = widget.primary ? const Color(0xFF0574F8) : Colors.white;
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

/// Двенадцать бледных лучей, полный оборот за минуту.
class _RaysPainter extends CustomPainter {
  _RaysPainter(this.centre, this.angle);
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
  bool shouldRepaint(_RaysPainter old) =>
      old.centre != centre || old.angle != angle;
}
