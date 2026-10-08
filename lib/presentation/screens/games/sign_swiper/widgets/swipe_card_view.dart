import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/data/models/sign_swiper_model.dart';
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
/// Плоская: обратная связь — подкрашивание зелёным/красным и значок по центру.
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
    with SingleTickerProviderStateMixin {
  static const double _threshold = 95.0;

  late final AnimationController _anim;
  Animation<Offset>? _offsetAnim;
  Animation<double>? _rotationAnim;

  Offset _drag = Offset.zero;
  bool _animatingOut = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    widget.controller?.attach(this);
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
    _anim.forward(from: 0).then((_) => onDone());
  }

  /// Программный свайп — по нажатию кнопки.
  void triggerSwipe(bool isRight) {
    if (_animatingOut) return;
    _animatingOut = true;
    _animate(
      toOffset: Offset(isRight ? 450 : -450, _drag.dy * 0.5),
      toAngle: isRight ? 0.35 : -0.35,
      curve: Curves.easeOutCubic,
      onDone: () {
        if (mounted) {
          setState(() {
            _drag = Offset.zero;
            _animatingOut = false;
            _offsetAnim = null;
            _rotationAnim = null;
          });
        }
        widget.onSwiped(isRight);
      },
    );
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (!_animatingOut) _anim.stop();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_animatingOut) return;
    setState(() => _drag += Offset(details.delta.dx, 0));
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
      _animate(
        toOffset: Offset.zero,
        toAngle: 0,
        curve: Curves.easeOutBack,
        onDone: () {
          if (mounted) setState(() => _drag = Offset.zero);
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final card = widget.card;

    return AnimatedBuilder(
      animation: _anim,
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.spacingXXL),
        child: LayoutBuilder(
          builder: (context, constraints) =>
              _buildContent(context, colors, constraints),
        ),
      ),
      builder: (context, child) {
        final animating =
            _anim.isAnimating && _offsetAnim != null && _rotationAnim != null;
        final offset = animating ? _offsetAnim!.value : _drag;
        final angle = animating ? _rotationAnim!.value : _drag.dx / 300 * 0.25;

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
          offset: offset,
          child: Transform.rotate(
            angle: angle,
            child: GestureDetector(
              onHorizontalDragStart: _onHorizontalDragStart,
              onHorizontalDragUpdate: _onHorizontalDragUpdate,
              onHorizontalDragEnd: _onHorizontalDragEnd,
              onTap: widget.onCardTap,
              child: Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: background,
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
      fontSize: 18,
      fontWeight: FontWeight.w600,
      height: 1.35,
      color: colors.primaryText,
    );
    final categoryStyle = TextStyle(fontSize: 12, color: colors.secondaryText);

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
        textHeight(card.sign.category, categoryStyle, maxLines: 1) -
        AppDimensions.spacingL -
        AppDimensions.spacingM;
    // На компактном экране сохраняем размер знака и весь вопрос; вертикальный
    // скролл не конкурирует с горизонтальным жестом ответа.
    final signHeight = remainingHeight.clamp(144.0, double.infinity);

    return SingleChildScrollView(
      primary: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(card.prompt, style: promptStyle),
          const SizedBox(height: AppDimensions.spacingL),
          SizedBox(
            height: signHeight,
            child: Center(child: _SignImage(sign: card.sign)),
          ),
          const SizedBox(height: AppDimensions.spacingM),
          Text(
            card.sign.category,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: categoryStyle,
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
