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
  final VoidCallback? onCardTap;
  final SwipeCardController? controller;

  const SwipeCardView({
    super.key,
    required this.card,
    required this.onSwiped,
    this.onCardTap,
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
  Animation<Offset>? _offsetAnim;
  Animation<double>? _rotationAnim;

  final _dragOffset = ValueNotifier<Offset>(Offset.zero);
  Offset get _drag => _dragOffset.value;
  set _drag(Offset value) => _dragOffset.value = value;
  bool _animatingOut = false;
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

  /// Программный свайп — по нажатию кнопки.
  void triggerSwipe(bool isRight) {
    if (_animatingOut) return;
    _animatingOut = true;
    _entrance.value = 1;
    if (!_thresholdTicked) HapticFeedbackHelper.select();
    _animate(
      toOffset: Offset(
        (MediaQuery.sizeOf(context).width + 100) * (isRight ? 1 : -1),
        -38,
      ),
      toAngle: isRight ? 0.20 : -0.20,
      curve: Curves.easeInQuad,
      onDone: () {
        if (mounted) {
          setState(() {
            _drag = Offset.zero;
            _animatingOut = false;
            _offsetAnim = null;
            _rotationAnim = null;
            _thresholdTicked = false;
          });
        }
        widget.onSwiped(isRight);
      },
    );
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (_animatingOut) return;
    _entrance.value = 1;
    // Picking up a returning card starts at its visible position.
    if (_anim.isAnimating) _drag = _offsetAnim?.value ?? _drag;
    _anim.stop();
    _offsetAnim = null;
    _rotationAnim = null;
    _thresholdTicked = false;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_animatingOut) return;
    // Only the transform/answer hint follows the finger; SVG, reflection
    // and question layout stay cached instead of rebuilding on each move.
    _drag += Offset(details.delta.dx, 0);
    if (!_thresholdTicked && _drag.dx.abs() >= _threshold) {
      _thresholdTicked = true;
      HapticFeedbackHelper.select();
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_animatingOut) return;

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
      animation: Listenable.merge([_anim, _entrance, _dragOffset]),
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
        final offset = animating ? _offsetAnim!.value : _drag;
        final angle = animating ? _rotationAnim!.value : _drag.dx / 300 * 0.25;
        final entrance = Curves.easeOutCubic.transform(_entrance.value);

        final progress = (offset.dx / _threshold).clamp(-1.0, 1.0);
        final strength = progress.abs();
        final isRight = progress > 0;
        final tint = isRight ? colors.green : colors.red;
        final background = Color.lerp(
          colors.cardBackground,
          tint,
          strength * 0.18,
        )!;

        return Transform.translate(
          offset: offset + Offset(0, 16 * (1 - entrance)),
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
              ..rotateY(-progress * 0.14)
              ..rotateZ(angle - 0.012 * (1 - entrance)),
            child: GestureDetector(
              onHorizontalDragStart: _onHorizontalDragStart,
              onHorizontalDragUpdate: _onHorizontalDragUpdate,
              onHorizontalDragEnd: _onHorizontalDragEnd,
              onHorizontalDragCancel: _returnToDeck,
              onTap: widget.onCardTap,
              child: Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      background,
                      Color.lerp(background, colors.accent, 0.07)!,
                    ],
                  ),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF536174)
                        : Colors.white,
                    width: 1.5,
                  ),
                  boxShadow: gameSoftShadow(colors),
                  borderRadius: BorderRadius.circular(
                    AppDimensions.radiusExtraLarge,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    child!,
                    if (strength > 0.15)
                      Opacity(
                        opacity: strength,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isRight
                                  ? Icons.check_circle_rounded
                                  : Icons.cancel_rounded,
                              size: 72,
                              color: tint,
                            ),
                            const SizedBox(height: AppDimensions.spacingS),
                            Text(
                              isRight
                                  ? card.rightActionLabel
                                  : card.leftActionLabel,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: tint,
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
        );
      },
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

    double textHeight(String text, TextStyle style, {int? maxLines}) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: DefaultTextStyle.of(context).style.merge(style),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: maxLines,
      )..layout(maxWidth: constraints.maxWidth);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    final remainingHeight =
        constraints.maxHeight -
        textHeight(card.prompt, promptStyle) -
        textHeight(appL10n.gameSignQuestionScope, scopeStyle) -
        AppDimensions.spacingL -
        AppDimensions.spacingM;
    // На компактном экране сохраняем размер знака и весь вопрос; вертикальный
    // скролл не конкурирует с горизонтальным жестом ответа.
    final signHeight = remainingHeight.clamp(160.0, 300.0);

    return SingleChildScrollView(
      primary: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(card.prompt, style: promptStyle),
          const SizedBox(height: AppDimensions.spacingL),
          SizedBox(
            height: signHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
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
          Text(
            appL10n.gameSignQuestionScope,
            textAlign: TextAlign.center,
            style: scopeStyle,
          ),
        ],
      ),
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
