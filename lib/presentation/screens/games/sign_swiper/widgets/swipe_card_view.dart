import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/data/models/sign_swiper_model.dart';

/// Контроллер для программного вызова свайпа карточки.
class SwipeCardController {
  SwipeCardViewState? _state;

  void attach(SwipeCardViewState state) {
    _state = state;
  }

  void detach(SwipeCardViewState state) {
    if (_state == state) {
      _state = null;
    }
  }

  void swipeLeft() => _state?.triggerSwipe(false);
  void swipeRight() => _state?.triggerSwipe(true);
}

/// Карточка свайпера с поддержкой жестов перетаскивания и наклона.
class SwipeCardView extends StatefulWidget {
  final SignCardQuestion card;
  final ValueChanged<bool> onSwiped; // true = вправо (ДА), false = влево (НЕТ)
  final bool isTopCard;
  final VoidCallback? onCardTap;
  final SwipeCardController? controller;

  const SwipeCardView({
    super.key,
    required this.card,
    required this.onSwiped,
    this.isTopCard = true,
    this.onCardTap,
    this.controller,
  });

  @override
  State<SwipeCardView> createState() => SwipeCardViewState();
}

class SwipeCardViewState extends State<SwipeCardView>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  Animation<Offset>? _offsetAnim;
  Animation<double>? _rotationAnim;

  Offset _dragOffset = Offset.zero;
  bool _isAnimatingOut = false;

  static const double _kSwipeThreshold = 95.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    if (widget.isTopCard) {
      widget.controller?.attach(this);
    }
  }

  @override
  void didUpdateWidget(covariant SwipeCardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detach(this);
      if (widget.isTopCard) {
        widget.controller?.attach(this);
      }
    }
    if (oldWidget.card.id != widget.card.id) {
      _animController.stop();
      _animController.reset();
      _dragOffset = Offset.zero;
      _isAnimatingOut = false;
      _offsetAnim = null;
      _rotationAnim = null;
    }
  }

  @override
  void dispose() {
    widget.controller?.detach(this);
    _animController.dispose();
    super.dispose();
  }

  /// Программный свайп (по нажатию на кнопку внизу).
  void triggerSwipe(bool isRight) {
    if (_isAnimatingOut || !widget.isTopCard) return;
    _isAnimatingOut = true;

    final targetX = isRight ? 450.0 : -450.0;
    _offsetAnim = Tween<Offset>(
      begin: _dragOffset,
      end: Offset(targetX, _dragOffset.dy * 0.5),
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));

    _rotationAnim = Tween<double>(
      begin: _dragOffset.dx / 300 * 0.25,
      end: (isRight ? 0.35 : -0.35),
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));

    _animController.forward(from: 0).then((_) {
      if (mounted) {
        setState(() {
          _dragOffset = Offset.zero;
          _isAnimatingOut = false;
          _offsetAnim = null;
          _rotationAnim = null;
        });
      }
      widget.onSwiped(isRight);
    });
  }

  void _onPanStart(DragStartDetails details) {
    if (!widget.isTopCard || _isAnimatingOut) return;
    _animController.stop();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!widget.isTopCard || _isAnimatingOut) return;
    setState(() {
      _dragOffset += details.delta;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (!widget.isTopCard || _isAnimatingOut) return;

    final velocityX = details.velocity.pixelsPerSecond.dx;
    final isRight = _dragOffset.dx > 0;
    final reachedThreshold = _dragOffset.dx.abs() > _kSwipeThreshold ||
        (velocityX.abs() > 450 && (_dragOffset.dx > 20 || _dragOffset.dx < -20));

    if (reachedThreshold) {
      triggerSwipe(isRight);
    } else {
      // Возврат на место пружиной
      _offsetAnim = Tween<Offset>(
        begin: _dragOffset,
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutBack));

      _rotationAnim = Tween<double>(
        begin: _dragOffset.dx / 300 * 0.25,
        end: 0.0,
      ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutBack));

      _animController.forward(from: 0).then((_) {
        if (mounted) {
          setState(() {
            _dragOffset = Offset.zero;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final card = widget.card;
    final sign = card.sign;

    // Рассчитываем текущие смещение и угол
    Offset currentOffset = _dragOffset;
    double currentAngle = (_dragOffset.dx / 300) * 0.25;

    if (_animController.isAnimating && _offsetAnim != null && _rotationAnim != null) {
      currentOffset = _offsetAnim!.value;
      currentAngle = _rotationAnim!.value;
    }

    final swipeProgress = (currentOffset.dx / _kSwipeThreshold).clamp(-1.0, 1.0);
    final isSwipingRight = currentOffset.dx > 10;
    final isSwipingLeft = currentOffset.dx < -10;

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        if (_animController.isAnimating && _offsetAnim != null && _rotationAnim != null) {
          currentOffset = _offsetAnim!.value;
          currentAngle = _rotationAnim!.value;
        }

        return Transform.translate(
          offset: currentOffset,
          child: Transform.rotate(
            angle: currentAngle,
            child: GestureDetector(
              onPanStart: widget.isTopCard ? _onPanStart : null,
              onPanUpdate: widget.isTopCard ? _onPanUpdate : null,
              onPanEnd: widget.isTopCard ? _onPanEnd : null,
              onTap: widget.onCardTap,
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 460),
                decoration: BoxDecoration(
                  color: colors.cardBackground,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: isSwipingRight
                        ? const Color(0xFF10B981).withValues(alpha: swipeProgress.abs().clamp(0.2, 0.9))
                        : isSwipingLeft
                            ? const Color(0xFFEF4444).withValues(alpha: swipeProgress.abs().clamp(0.2, 0.9))
                            : colors.divider,
                    width: swipeProgress.abs() > 0.2 ? 2.5 : 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isSwipingRight
                          ? const Color(0xFF10B981).withValues(alpha: 0.15 * swipeProgress.abs())
                          : isSwipingLeft
                              ? const Color(0xFFEF4444).withValues(alpha: 0.15 * swipeProgress.abs())
                              : Colors.black.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Stack(
                    children: [
                      // Контент карточки
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Категория / Номер бейдж
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: colors.secondaryText.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    sign.number,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: colors.primaryText,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    sign.category,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: colors.secondaryText,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Вопрос / Утверждение
                            Text(
                              card.prompt,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: colors.primaryText,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Графика знака
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: colors.homeScreenBackground.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Center(
                                  child: _buildSignImage(sign, colors),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Народное имя или подсказка
                            if (sign.folkName != null) ...[
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    'В народе: «${sign.folkName}»',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.amber,
                                    ),
                                  ),
                                ),
                              ),
                            ] else ...[
                              Center(
                                child: Text(
                                  'Свайп вправо — ДА • влево — НЕТ',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.secondaryText.withValues(alpha: 0.7),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Оверлей бейджа «ДА / ВЕРНО» (появляется при свайпе вправо)
                      if (isSwipingRight)
                        Positioned(
                          top: 24,
                          left: 20,
                          child: Transform.rotate(
                            angle: -0.2,
                            child: Opacity(
                              opacity: swipeProgress.abs().clamp(0.0, 1.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 8,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                                    SizedBox(width: 6),
                                    Text(
                                      'ДА / ВЕРНО',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                      // Оверлей бейджа «НЕТ / НЕВЕРНО» (появляется при свайпе влево)
                      if (isSwipingLeft)
                        Positioned(
                          top: 24,
                          right: 20,
                          child: Transform.rotate(
                            angle: 0.2,
                            child: Opacity(
                              opacity: swipeProgress.abs().clamp(0.0, 1.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 8,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.cancel_rounded, color: Colors.white, size: 20),
                                    SizedBox(width: 6),
                                    Text(
                                      'НЕТ / НЕВЕРНО',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
      },
    );
  }

  Widget _buildSignImage(SignItem sign, dynamic colors) {
    if (sign.image.endsWith('.svg')) {
      return SvgPicture.asset(
        sign.assetPath,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => const CircularProgressIndicator.adaptive(),
      );
    }
    return Image.asset(
      sign.assetPath,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.signpost_rounded,
        size: 80,
        color: colors.secondaryText,
      ),
    );
  }
}
