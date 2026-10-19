import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/sign_swiper_model.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/games/widgets/game_ui.dart';

/// Контроллер для программного свайпа карточки (кнопки внизу).
class SwipeCardController {
  SwipeCardViewState? _state;

  void attach(SwipeCardViewState state) => _state = state;

  void detach(SwipeCardViewState state) {
    if (_state == state) _state = null;
  }

  void swipeLeft() => _state?.triggerSwipe(false);
  void swipeRight() => _state?.triggerSwipe(true);
}

/// Карточка знака. Тянется пальцем; вправо — «да», влево — «нет».
/// Объёмная карточка с настоящим знаком из общей базы приложения.
class SwipeCardView extends StatefulWidget {
  final SignCardQuestion card;
  final ValueChanged<bool> onSwiped; // true = вправо (ДА), false = влево (НЕТ)
  /// Called when the answer is locked, before feedback and departure.
  final ValueChanged<bool>? onAnswered;
  final VoidCallback? onCardTap;
  final bool enabled;
  final SwipeCardController? controller;

  const SwipeCardView({
    super.key,
    required this.card,
    required this.onSwiped,
    this.onAnswered,
    this.onCardTap,
    this.enabled = true,
    this.controller,
  });

  @override
  State<SwipeCardView> createState() => SwipeCardViewState();
}

class SwipeCardViewState extends State<SwipeCardView>
    with TickerProviderStateMixin {
  static const double _threshold = 95.0;

  late final AnimationController _anim;
  late final AnimationController _entrance;
  late final AnimationController _feedback;
  bool? _answer;
  bool get _correct => _answer == widget.card.isCorrect;
  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);
  Animation<Offset>? _offsetAnim;
  Animation<double>? _rotationAnim;

  final _dragOffset = ValueNotifier<Offset>(Offset.zero);
  Offset get _drag => _dragOffset.value;
  set _drag(Offset value) => _dragOffset.value = value;
  bool _animatingOut = false;
  bool _departing = false;
  bool _entered = false;
  bool _thresholdTicked = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _feedback = AnimationController(vsync: this);
    widget.controller?.attach(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _anim.duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 240);
    if (reduceMotion) {
      _entrance.value = 1;
    } else if (!_entered) {
      _entrance.forward();
    }
    _entered = true;
  }

  @override
  void didUpdateWidget(covariant SwipeCardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detach(this);
      widget.controller?.attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?.detach(this);
    _anim.dispose();
    _entrance.dispose();
    _feedback.dispose();
    _dragOffset.dispose();
    super.dispose();
  }

  void _animate({
    required Offset toOffset,
    required double toAngle,
    required Curve curve,
    required VoidCallback onDone,
  }) {
    _offsetAnim = Tween<Offset>(
      begin: _drag,
      end: toOffset,
    ).animate(CurvedAnimation(parent: _anim, curve: curve));
    _rotationAnim = Tween<double>(
      begin: _drag.dx / 300 * 0.25,
      end: toAngle,
    ).animate(CurvedAnimation(parent: _anim, curve: curve));
    _anim.forward(from: 0).then((_) {
      if (mounted) onDone();
    });
  }

  /// Commit once, bring the card back into view, then show the actual result.
  /// Red/green while dragging means NO/YES; only this result means wrong/right.
  Future<void> triggerSwipe(bool isRight) async {
    if (_animatingOut || !widget.enabled) return;
    _animatingOut = true;
    _entrance.value = 1;
    if (!_thresholdTicked) HapticFeedbackHelper.select();
    setState(() => _answer = isRight);
    widget.onAnswered?.call(isRight);
    try {
      _offsetAnim = Tween<Offset>(
        begin: _drag,
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
      _rotationAnim = Tween<double>(
        begin: _drag.dx / 300 * 0.25,
        end: 0,
      ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
      _anim.duration = _reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 150);
      await _anim.forward(from: 0).orCancel;
      if (!mounted) return;
      _drag = Offset.zero;
      _offsetAnim = null;
      _rotationAnim = null;
      _feedback.duration = Duration(milliseconds: _correct ? 400 : 950);
      await _feedback.forward(from: 0).orCancel;
      if (!mounted) return;
      _departing = true;
      _anim.duration = _reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 320);
      _offsetAnim = Tween<Offset>(
        begin: Offset.zero,
        end: Offset(
          (MediaQuery.sizeOf(context).width + 160) * (isRight ? 1 : -1),
          -90,
        ),
      ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeInCubic));
      _rotationAnim = Tween<double>(
        begin: 0,
        end: isRight ? 0.32 : -0.32,
      ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeInCubic));
      await _anim.forward(from: 0).orCancel;
      if (!mounted) return;
      widget.onSwiped(isRight);
      if (!mounted) return;
      setState(() {
        _drag = Offset.zero;
        _animatingOut = false;
        _departing = false;
        _offsetAnim = null;
        _rotationAnim = null;
        _thresholdTicked = false;
        _answer = null;
        _feedback.reset();
      });
    } on TickerCanceled {
      // Navigation or round completion disposed the card mid-animation.
    }
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (_animatingOut || !widget.enabled) return;
    _entrance.value = 1;
    // Picking up a returning card starts at its visible position.
    if (_anim.isAnimating) _drag = _offsetAnim?.value ?? _drag;
    _anim.stop();
    _offsetAnim = null;
    _rotationAnim = null;
    _thresholdTicked = false;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_animatingOut || !widget.enabled) return;
    // Only the transform/answer hint follows the finger; SVG, reflection
    // and question layout stay cached instead of rebuilding on each move.
    _drag += Offset(details.delta.dx, 0);
    if (!_thresholdTicked && _drag.dx.abs() >= _threshold) {
      _thresholdTicked = true;
      HapticFeedbackHelper.select();
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_animatingOut || !widget.enabled) return;

    final velocityX = details.velocity.pixelsPerSecond.dx;
    final reached =
        _drag.dx.abs() > _threshold ||
        (velocityX.abs() > 450 && _drag.dx.abs() > 20);

    if (reached) {
      triggerSwipe(_drag.dx > 0);
    } else {
      _returnToDeck();
    }
  }

  void _returnToDeck() {
    if (_animatingOut || (_drag == Offset.zero && !_anim.isAnimating)) return;
    _animate(
      toOffset: Offset.zero,
      toAngle: 0,
      curve: Curves.easeOutCubic,
      onDone: () => setState(() {
        _drag = Offset.zero;
        _offsetAnim = null;
        _rotationAnim = null;
        _thresholdTicked = false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final card = widget.card;

    return AnimatedBuilder(
      animation: Listenable.merge([_anim, _entrance, _feedback, _dragOffset]),
      child: RepaintBoundary(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.spacingXXL),
          child: LayoutBuilder(
            builder: (context, constraints) =>
                _buildContent(context, colors, constraints),
          ),
        ),
      ),
      builder: (context, child) {
        final animating =
            _anim.isAnimating && _offsetAnim != null && _rotationAnim != null;
        var offset = animating ? _offsetAnim!.value : _drag;
        if (_departing) {
          offset = Offset(offset.dx, -90 * math.sin(_anim.value * math.pi / 2));
        }
        final angle = animating ? _rotationAnim!.value : _drag.dx / 300 * 0.25;
        final entrance = Curves.easeOutBack.transform(_entrance.value);
        final showingResult = _answer != null;
        final shake = showingResult && !_correct && !_reduceMotion
            ? math.sin(_feedback.value * math.pi * 10) *
                  9 *
                  math.pow(1 - _feedback.value, 3)
            : 0.0;
        final reveal = showingResult
            ? (_reduceMotion
                  ? 1.0
                  : Curves.easeOut.transform(
                      (_feedback.value * 6).clamp(0.0, 1.0),
                    ))
            : 0.0;

        final progress = (offset.dx / _threshold).clamp(-1.0, 1.0);
        final strength = progress.abs();
        final isRight = progress > 0;
        final tint = showingResult
            ? (_correct ? colors.green : colors.red)
            : (isRight ? colors.green : colors.red);
        final background = Color.lerp(
          colors.cardBackground,
          tint,
          showingResult ? 0.12 * reveal : strength * 0.10,
        )!;

        return Transform.translate(
          offset:
              (_reduceMotion ? Offset.zero : offset) +
              Offset(
                shake,
                _reduceMotion ? 0 : 24 * (1 - entrance) - strength * 8,
              ),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..scaleByDouble(
                0.97 + 0.03 * entrance,
                0.97 + 0.03 * entrance,
                1,
                1,
              )
              ..rotateX(_reduceMotion ? 0 : 0.025 * entrance)
              ..rotateY(_reduceMotion ? 0 : -progress * 0.22)
              ..rotateZ(_reduceMotion ? 0 : angle - 0.025 * (1 - entrance)),
            child: GestureDetector(
              onHorizontalDragStart: _onHorizontalDragStart,
              onHorizontalDragUpdate: _onHorizontalDragUpdate,
              onHorizontalDragEnd: _onHorizontalDragEnd,
              onHorizontalDragCancel: _returnToDeck,
              onTap: widget.enabled && !_animatingOut ? widget.onCardTap : null,
              child: Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(
                        background,
                        colors.white,
                        colors.isDark ? 0.06 : 0.5,
                      )!,
                      background,
                      Color.lerp(background, colors.accent, 0.09)!,
                    ],
                  ),
                  border: Border.all(
                    color: showingResult
                        ? tint.withValues(alpha: 0.45 + 0.55 * reveal)
                        : Color.lerp(
                            colors.cardBackground,
                            colors.accent,
                            0.18,
                          )!,
                    width: showingResult ? 3 : 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color.lerp(
                        colors.cardBackground,
                        colors.accent,
                        0.25,
                      )!,
                      offset: const Offset(0, 6),
                    ),
                    ...gameSoftShadow(colors),
                  ],
                  borderRadius: BorderRadius.circular(
                    AppDimensions.radiusExtraLarge,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    child!,
                    if (!showingResult && strength > 0.08)
                      Positioned(
                        top: 16,
                        left: isRight ? null : 16,
                        right: isRight ? 16 : null,
                        child: Opacity(
                          opacity: strength,
                          child: _answerChip(
                            colors,
                            isRight
                                ? card.rightActionLabel
                                : card.leftActionLabel,
                            isRight ? Icons.east_rounded : Icons.west_rounded,
                            tint,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _answerChip(
    AppThemeColors colors,
    String label,
    IconData icon,
    Color tint,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        border: Border.all(color: tint, width: 2),
        borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: tint),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: tint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    AppThemeColors colors,
    BoxConstraints constraints,
  ) {
    final card = widget.card;
    final promptStyle = TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.25,
      color: colors.primaryText,
    );
    final scopeStyle = TextStyle(fontSize: 11, color: colors.secondaryText);

    double textHeight(String text, TextStyle style, {double? width}) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: DefaultTextStyle.of(context).style.merge(style),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: width ?? constraints.maxWidth);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    final answerStyle = const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );
    final footerHeight =
        math.max(
          textHeight(appL10n.gameSignQuestionScope, scopeStyle),
          math.max(
                22.0,
                textHeight(
                  appL10n.signSwiperIncorrect,
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  width: math.max(1.0, constraints.maxWidth - 44),
                ),
              ) +
              math.max(
                textHeight(
                  appL10n.signSwiperCorrectAnswer(card.rightActionLabel),
                  answerStyle,
                  width: math.max(1.0, constraints.maxWidth - 16),
                ),
                textHeight(
                  appL10n.signSwiperCorrectAnswer(card.leftActionLabel),
                  answerStyle,
                  width: math.max(1.0, constraints.maxWidth - 16),
                ),
              ) +
              20,
        ) +
        8;
    final remainingHeight =
        constraints.maxHeight -
        textHeight(card.prompt, promptStyle) -
        footerHeight -
        AppDimensions.spacingL -
        AppDimensions.spacingM;
    // На компактном экране сохраняем размер знака и весь вопрос; вертикальный
    // скролл не конкурирует с горизонтальным жестом ответа.
    final signHeight = remainingHeight.clamp(160.0, 300.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            primary: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  card.prompt,
                  textAlign: TextAlign.center,
                  style: promptStyle,
                ),
                const SizedBox(height: AppDimensions.spacingL),
                SizedBox(
                  height: signHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 10,
                    ),
                    child: ShaderMask(
                      // Specular light follows the actual SVG alpha, including
                      // triangles/circles. No rectangular plate or new bitmap.
                      blendMode: BlendMode.srcATop,
                      shaderCallback: (bounds) => const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0x0A10263C),
                          Color(0x00FFFFFF),
                          Color(0x38FFFFFF),
                          Color(0x0CFFFFFF),
                          Color(0x00FFFFFF),
                          Color(0x1010263C),
                        ],
                        stops: [0, 0.28, 0.42, 0.48, 0.59, 1],
                      ).createShader(bounds),
                      child: _SignImage(sign: card.sign),
                    ),
                  ),
                ),
                const SizedBox(height: AppDimensions.spacingM),
              ],
            ),
          ),
        ),
        SizedBox(
          height: footerHeight,
          child: Center(
            child: _answer == null
                ? Text(
                    appL10n.gameSignQuestionScope,
                    textAlign: TextAlign.center,
                    style: scopeStyle,
                  )
                : Semantics(
                    liveRegion: true,
                    child: Container(
                      key: const ValueKey('sign-answer-feedback'),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _correct ? colors.greenLight : colors.redLight,
                        borderRadius: BorderRadius.circular(
                          AppDimensions.radiusLarge,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _correct
                                    ? Icons.check_circle_rounded
                                    : Icons.cancel_rounded,
                                color: _correct ? colors.green : colors.red,
                                size: 22,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _correct
                                      ? appL10n.gameCorrect
                                      : appL10n.signSwiperIncorrect,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: _correct
                                        ? colors.primaryText
                                        : colors.red,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (!_correct) ...[
                            const SizedBox(height: 4),
                            Text(
                              appL10n.signSwiperCorrectAnswer(
                                card.isCorrect
                                    ? card.rightActionLabel
                                    : card.leftActionLabel,
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colors.primaryText,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _SignImage extends StatelessWidget {
  const _SignImage({required this.sign});

  final SignItem sign;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (sign.image.endsWith('.svg')) {
      return SvgPicture.asset(sign.assetPath, fit: BoxFit.contain);
    }
    return Image.asset(
      sign.assetPath,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) =>
          Icon(Icons.signpost_rounded, size: 80, color: colors.secondaryText),
    );
  }
}
