import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/sign_swiper_model.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/games/widgets/mini_game_hud.dart';

/// Контроллер карточки: программный свайп (кнопки внизу) и её положение.
/// Кнопки ответа и следующая карточка колоды следят за [lean] и [reveal],
/// поэтому направление ответа видно без надписей поверх вопроса.
class SwipeCardController {
  SwipeCardViewState? _state;

  /// −1…1: куда отведена карточка; во время итога — выбранная сторона,
  /// а при ошибке затем сторона верного ответа.
  final ValueNotifier<double> lean = ValueNotifier(0);

  /// 0…1: насколько верхняя карточка освободила колоду.
  final ValueNotifier<double> reveal = ValueNotifier(0);

  void attach(SwipeCardViewState state) => _state = state;

  void detach(SwipeCardViewState state) {
    if (_state == state) _state = null;
  }

  void swipeLeft() => _state?.triggerSwipe(false);
  void swipeRight() => _state?.triggerSwipe(true);

  void dispose() {
    lean.dispose();
    reveal.dispose();
  }
}

/// Карточка знака. Тянется пальцем; вправо — «да», влево — «нет».
/// Сверху — знак на светлой подложке, под ним вопрос; итог ответа — в нижней
/// строке карточки и на подложке знака, текст ничем не перекрывается.
class SwipeCardView extends StatefulWidget {
  final SignCardQuestion card;
  final ValueChanged<bool> onSwiped; // true = вправо (ДА), false = влево (НЕТ)
  /// Called when the answer is locked, before feedback and departure.
  final ValueChanged<bool>? onAnswered;
  final VoidCallback? onCardTap;
  final bool enabled;
  final SwipeCardController? controller;

  /// Первая карточка раунда поднимается снизу; следующие уже лежат на месте
  /// поднявшейся карточки колоды ([SignDeckCard]) и не анимируются заново.
  final bool animateIn;

  /// Один раз показать жест: карточка слегка отходит вправо и влево.
  final bool teach;

  const SwipeCardView({
    super.key,
    required this.card,
    required this.onSwiped,
    this.onAnswered,
    this.onCardTap,
    this.enabled = true,
    this.controller,
    this.animateIn = true,
    this.teach = false,
  });

  @override
  State<SwipeCardView> createState() => SwipeCardViewState();
}

class SwipeCardViewState extends State<SwipeCardView>
    with TickerProviderStateMixin {
  static const double _threshold = 95.0;

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final AnimationController _feedback = AnimationController(vsync: this);
  late final AnimationController _lift = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    reverseDuration: const Duration(milliseconds: 260),
  );
  late final AnimationController _hint = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2100),
  );
  // Pause, a lean towards «yes», towards «no», and back to rest.
  late final Animation<double> _hintOffset = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(0), weight: 900),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0,
        end: 34,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 360,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 34,
        end: -30,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 480,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: -30,
        end: 0,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 360,
    ),
  ]).animate(_hint);

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
  bool _armed = false;
  double _width = 340;
  double _committedLean = 0;

  /// −1…1 for the sign plate and outline: drag direction, then the verdict.
  final _tint = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    widget.controller?.attach(this);
    for (final listenable in [_anim, _feedback, _hint, _dragOffset]) {
      listenable.addListener(_publish);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entered) return;
    _entered = true;
    if (_reduceMotion || !widget.animateIn) {
      _entrance.value = 1;
    } else {
      _entrance.forward();
    }
    if (widget.teach && widget.enabled && !_reduceMotion) _hint.forward();
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
    _lift.dispose();
    _hint.dispose();
    _dragOffset.dispose();
    _tint.dispose();
    super.dispose();
  }

  Offset get _visibleOffset {
    final animating = _anim.isAnimating && _offsetAnim != null;
    final offset = animating ? _offsetAnim!.value : _drag;
    return offset + Offset(_hintOffset.value, 0);
  }

  /// The side whose answer is shown: the chosen one, and for a mistake the
  /// right one once the card has settled.
  void _publish() {
    final controller = widget.controller;
    final answer = _answer;
    double lean, reveal;
    if (answer == null) {
      lean = (_visibleOffset.dx / _threshold).clamp(-1.0, 1.0);
      reveal = 0.3 * lean.abs();
      // While dragging the tint is the direction: green YES, red NO.
      _tint.value = lean;
    } else {
      final chosen = answer ? 1.0 : -1.0;
      final right = widget.card.isCorrect ? 1.0 : -1.0;
      if (_departing) {
        final t = _anim.value;
        lean = right * (1 - t);
        reveal = 0.3 + 0.7 * Curves.easeOut.transform(t);
      } else if (_feedback.value > 0 || _feedback.isAnimating) {
        // A mistake hands the light over to the right answer's button.
        final swap = Curves.easeInOut.transform(
          (_feedback.value * 3).clamp(0.0, 1.0),
        );
        lean = _correct ? chosen : chosen + (right - chosen) * swap;
        reveal = 0.3;
      } else {
        // Coming back to the middle: the chosen button stays lit.
        lean = chosen * math.max(_committedLean, _anim.value);
        reveal = 0.3;
      }
      // After the answer the tint is the verdict: green right, red wrong.
      _tint.value = _correct ? 1.0 : -1.0;
    }
    if (controller != null) {
      controller.lean.value = lean;
      controller.reveal.value = reveal;
    }
  }

  void _stopHint() {
    if (!_hint.isAnimating && _hint.value == 0) return;
    _drag = _drag + Offset(_hintOffset.value, 0);
    _hint
      ..stop()
      ..value = 0;
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
      begin: _angleFor(_drag.dx),
      end: toAngle,
    ).animate(CurvedAnimation(parent: _anim, curve: curve));
    _anim.forward(from: 0).then((_) {
      if (mounted) onDone();
    });
  }

  double _angleFor(double dx) => dx / _width * 0.32;

  /// Commit once, bring the card back into view, then show the actual result.
  /// While dragging the buttons below show the direction (NO/YES); only this
  /// result means wrong/right.
  Future<void> triggerSwipe(bool isRight) async {
    if (_animatingOut || !widget.enabled) return;
    _animatingOut = true;
    _stopHint();
    _entrance.value = 1;
    if (!_armed) HapticFeedbackHelper.select();
    _committedLean = (_drag.dx / _threshold).abs().clamp(0.0, 1.0);
    setState(() => _answer = isRight);
    widget.onAnswered?.call(isRight);
    _publish();
    try {
      _offsetAnim = Tween<Offset>(
        begin: _drag,
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutBack));
      _rotationAnim = Tween<double>(
        begin: _angleFor(_drag.dx),
        end: 0,
      ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutBack));
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
      // A wrong card leaves towards the right answer, a right one keeps going.
      final towardsRight = _correct ? isRight : widget.card.isCorrect;
      SoundEffectsService.instance.playSwipe();
      _anim.duration = _reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 320);
      _offsetAnim = Tween<Offset>(
        begin: Offset.zero,
        end: Offset(
          (MediaQuery.sizeOf(context).width + 200) * (towardsRight ? 1 : -1),
          0,
        ),
      ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeInCubic));
      _rotationAnim = Tween<double>(
        begin: 0,
        end: towardsRight ? 0.36 : -0.36,
      ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeInCubic));
      await _anim.forward(from: 0).orCancel;
      if (!mounted) return;
      // The next card has already risen: hand over before it rebuilds.
      widget.controller?.lean.value = 0;
      widget.controller?.reveal.value = 0;
      widget.onSwiped(isRight);
      if (!mounted) return;
      setState(() {
        _drag = Offset.zero;
        _animatingOut = false;
        _departing = false;
        _offsetAnim = null;
        _rotationAnim = null;
        _armed = false;
        _answer = null;
        _committedLean = 0;
        _feedback.reset();
        _tint.value = 0;
      });
    } on TickerCanceled {
      // Navigation or round completion disposed the card mid-animation.
    }
  }

  void _onPointerDown(PointerDownEvent _) {
    if (_animatingOut || !widget.enabled || _reduceMotion) return;
    _lift.forward();
  }

  void _onPointerUp(PointerEvent _) {
    if (_lift.value > 0 || _lift.isAnimating) _lift.reverse();
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (_animatingOut || !widget.enabled) return;
    _stopHint();
    _entrance.value = 1;
    // Picking up a returning card starts at its visible position.
    if (_anim.isAnimating) _drag = _offsetAnim?.value ?? _drag;
    _anim.stop();
    _offsetAnim = null;
    _rotationAnim = null;
    _armed = _drag.dx.abs() >= _threshold;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_animatingOut || !widget.enabled) return;
    // Only the transform and the tints follow the finger; the SVG and the
    // question layout stay cached instead of rebuilding on each move.
    _drag += Offset(details.delta.dx, 0);
    final armed = _drag.dx.abs() >= _threshold;
    if (armed != _armed) {
      // A light tick both when the answer is armed and when it is released.
      _armed = armed;
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
    _anim.duration = _reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 380);
    _animate(
      toOffset: Offset.zero,
      toAngle: 0,
      curve: Curves.easeOutBack,
      onDone: () => setState(() {
        _drag = Offset.zero;
        _offsetAnim = null;
        _rotationAnim = null;
        _armed = false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth.isFinite) _width = constraints.maxWidth;
        return AnimatedBuilder(
          animation: Listenable.merge([
            _anim,
            _entrance,
            _feedback,
            _lift,
            _hint,
            _dragOffset,
          ]),
          child: Listener(
            onPointerDown: _onPointerDown,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerUp,
            child: GestureDetector(
              onHorizontalDragStart: _onHorizontalDragStart,
              onHorizontalDragUpdate: _onHorizontalDragUpdate,
              onHorizontalDragEnd: _onHorizontalDragEnd,
              onHorizontalDragCancel: _returnToDeck,
              onTap: widget.enabled && !_animatingOut ? widget.onCardTap : null,
              child: _CardSurface(
                tint: _tint,
                verdict: _answer == null ? null : _correct,
                lift: _lift,
                child: SignCardFace(
                  card: widget.card,
                  tint: _tint,
                  verdict: _answer == null ? null : _correct,
                  progress: _feedback,
                  feedback: _answer == null ? null : _buildFeedback(colors),
                ),
              ),
            ),
          ),
          builder: (context, child) {
            final reduce = _reduceMotion;
            final animating =
                _anim.isAnimating &&
                _offsetAnim != null &&
                _rotationAnim != null;
            var offset = _visibleOffset;
            if (_departing) {
              // A short upward arc on the way out.
              offset += Offset(0, -56 * math.sin(_anim.value * math.pi / 2));
            }
            final angle = animating
                ? _rotationAnim!.value
                : _angleFor(offset.dx);
            final entrance = Curves.easeOutCubic.transform(_entrance.value);
            final settle = Curves.easeOutBack.transform(_entrance.value);
            final verdict = _answer != null && !_departing;
            final fb = _feedback.value;
            final shake = verdict && !_correct && !reduce
                ? math.sin(fb * math.pi * 10) * 9 * math.pow(1 - fb, 3)
                : 0.0;
            final nod = verdict && _correct && !reduce
                ? 0.025 * math.sin(math.pi * fb)
                : 0.0;
            final lift = Curves.easeOut.transform(_lift.value);
            final scale = (0.94 + 0.06 * settle) * (1 + 0.015 * lift) + nod;

            return Opacity(
              opacity: reduce ? 1 : entrance,
              child: Transform.translate(
                offset: reduce
                    ? Offset.zero
                    : offset + Offset(shake, 36 * (1 - entrance)),
                child: Transform.rotate(
                  angle: reduce ? 0 : angle,
                  // Held near the bottom, the top swings out like a real card.
                  alignment: const Alignment(0, 0.9),
                  child: Transform.scale(
                    scale: reduce ? 1 : scale,
                    child: child,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFeedback(AppThemeColors colors) {
    final card = widget.card;
    final correct = _correct;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('sign-answer-feedback'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: correct ? colors.greenLight : colors.redLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!correct)
              const GameLifeLossBadge()
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: colors.green,
                    size: 22,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      appL10n.gameCorrect,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                ],
              ),
            if (!correct) ...[
              const SizedBox(height: 4),
              Text(
                appL10n.signSwiperCorrectAnswer(
                  card.isCorrect ? card.rightActionLabel : card.leftActionLabel,
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
    );
  }
}

/// Поверхность карточки: белая (в тёмной теме — цвет карточек), мягкая тень
/// в светлой теме, тонкий контур цвета ответа — при отводе и в итоге.
class _CardSurface extends StatelessWidget {
  const _CardSurface({
    required this.tint,
    required this.verdict,
    required this.lift,
    required this.child,
  });

  final ValueListenable<double> tint;
  final bool? verdict;
  final Animation<double> lift;
  final Widget child;

  static const radius = BorderRadius.all(Radius.circular(28));

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([tint, lift]),
      child: child,
      builder: (context, child) {
        final t = tint.value;
        final strength = verdict != null ? 1.0 : t.abs();
        final color = t >= 0 ? colors.green : colors.red;
        final up = lift.value;
        return Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: radius,
            boxShadow: colors.isDark
                ? null
                : [
                    BoxShadow(
                      color: Color.lerp(
                        const Color(0x12101828),
                        const Color(0x1F101828),
                        up,
                      )!,
                      blurRadius: 28 + 12 * up,
                      offset: Offset(0, 12 + 6 * up),
                    ),
                  ],
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: color.withValues(alpha: strength.clamp(0.0, 1.0)),
              width: 2.5,
            ),
          ),
          child: child,
        );
      },
    );
  }
}

/// Содержимое карточки: знак на подложке, вопрос и нижняя строка (охват
/// вопроса или итог ответа). Общая для верхней карточки и карточки колоды.
class SignCardFace extends StatelessWidget {
  const SignCardFace({
    super.key,
    required this.card,
    this.tint,
    this.verdict,
    this.progress,
    this.feedback,
    this.scrollable = true,
  });

  final SignCardQuestion card;

  /// −1…1: направление отвода — подложка знака теплеет к цвету ответа.
  final ValueListenable<double>? tint;

  /// Итог: true — верно, false — ошибка, null — ещё нет ответа.
  final bool? verdict;

  /// Ход показа итога (0…1): значок на подложке и строка итога появляются.
  final Animation<double>? progress;
  final Widget? feedback;

  /// Карточка колоды не прокручивается: длинный вопрос обрезается снизу.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final promptStyle = TextStyle(
      fontSize: 21,
      fontWeight: FontWeight.w700,
      height: 1.28,
      letterSpacing: -0.2,
      color: colors.primaryText,
    );
    final scopeStyle = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w500,
      color: colors.secondaryText,
    );

    return Padding(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, constraints) {
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

          const answerStyle = TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          );
          final footerHeight =
              math.max(
                textHeight(appL10n.gameSignQuestionScope, scopeStyle),
                math.max(
                      24.0,
                      textHeight(
                        '−1',
                        const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
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
          final remaining =
              constraints.maxHeight -
              textHeight(card.prompt, promptStyle) -
              footerHeight -
              16 -
              12;
          // На компактном экране сохраняем размер знака и весь вопрос;
          // вертикальная прокрутка не конкурирует с горизонтальным жестом.
          final plateHeight = remaining.clamp(150.0, 300.0);

          final body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: plateHeight,
                child: _SignPlate(
                  sign: card.sign,
                  tint: tint,
                  verdict: verdict,
                  progress: progress,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                card.prompt,
                textAlign: TextAlign.center,
                style: promptStyle,
              ),
              const SizedBox(height: 12),
            ],
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: scrollable
                    ? SingleChildScrollView(primary: false, child: body)
                    : ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.topCenter,
                          maxHeight: double.infinity,
                          child: body,
                        ),
                      ),
              ),
              SizedBox(
                height: footerHeight,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.88,
                          end: 1,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child:
                        feedback ??
                        Text(
                          appL10n.gameSignQuestionScope,
                          key: const ValueKey('sign-question-scope'),
                          textAlign: TextAlign.center,
                          style: scopeStyle,
                        ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Подложка знака: светлая плашка карточки; при отводе мягко принимает цвет
/// ответа, в итоге — цвет результата и значок в углу.
class _SignPlate extends StatelessWidget {
  const _SignPlate({
    required this.sign,
    required this.tint,
    required this.verdict,
    required this.progress,
  });

  final SignItem sign;
  final ValueListenable<double>? tint;
  final bool? verdict;
  final Animation<double>? progress;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final image = Padding(
      padding: const EdgeInsets.all(18),
      child: _SignImage(sign: sign),
    );
    final listenable = Listenable.merge([?tint, ?progress]);
    return AnimatedBuilder(
      animation: listenable,
      child: image,
      builder: (context, child) {
        final t = tint?.value ?? 0;
        final strength = verdict != null ? 1.0 : t.abs();
        final target = t >= 0 ? colors.greenLight : colors.redLight;
        final plate = Color.lerp(colors.gray, target, strength * 0.9)!;
        final pop = verdict == null
            ? 0.0
            : Curves.easeOutBack.transform(
                ((progress?.value ?? 1) * 2.4).clamp(0.0, 1.0),
              );
        return DecoratedBox(
          decoration: BoxDecoration(
            color: plate,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              child!,
              if (verdict != null)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Transform.scale(
                    scale: pop,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: verdict! ? colors.green : colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        verdict! ? Icons.check_rounded : Icons.close_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Следующая карточка колоды под верхней: настоящий знак и вопрос, чуть
/// меньше и приглушённее. Поднимается, пока верхнюю отводят и уводят, и к
/// концу вылета стоит ровно там, где её сменит новая верхняя карточка.
class SignDeckCard extends StatelessWidget {
  const SignDeckCard({super.key, required this.card, required this.reveal});

  final SignCardQuestion card;
  final ValueListenable<double> reveal;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final face = IgnorePointer(
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: _CardSurface.radius,
          ),
          child: SignCardFace(card: card, scrollable: false),
        ),
      ),
    );
    return ValueListenableBuilder<double>(
      valueListenable: reveal,
      child: face,
      builder: (context, value, child) {
        final r = MediaQuery.disableAnimationsOf(context) ? 0.0 : value;
        return Transform.translate(
          offset: Offset(0, 22 * (1 - r)),
          child: Transform.scale(
            scale: 0.94 + 0.06 * r,
            child: Stack(
              fit: StackFit.expand,
              children: [
                child!,
                // Dimmed like a card further away; fades as it comes up.
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.background.withValues(
                        alpha: 0.55 * (1 - r),
                      ),
                      borderRadius: _CardSurface.radius,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
