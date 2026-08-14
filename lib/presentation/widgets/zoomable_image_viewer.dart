import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Полноэкранный просмотр картинки с зумом.
///
/// Зачем: на картинках вопросов детали мелкие (номера на знаках, разметка,
/// положение машин), и на телефоне их часто не разглядеть. Отзыв в RuStore
/// «Картинки не увеличиваются при просмотре» — ровно про это.
///
/// Управление:
/// - щипок двумя пальцами — увеличение до 5×; когда пальцы отпускают,
///   картинка сама возвращается в исходное (как в ленте Instagram);
/// - двойное нажатие — зум 2,5× в точку нажатия, и он ОСТАЁТСЯ: именно так
///   деталь можно спокойно рассмотреть и подвигать;
/// - свайп вниз, кнопка «назад» или крестик — выход.
Future<void> showZoomableImage({
  required BuildContext context,
  required Widget image,
  required Object heroTag,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 340),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, _, _) =>
          _ZoomableImageScreen(image: image, heroTag: heroTag),
      // Фон затемняется отдельно от полёта картинки: Hero ведёт саму
      // картинку, а тут — только чернота под ней, чтобы открытие читалось
      // как «картинка выросла из карточки», а не как подмена экрана.
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    ),
  );
}

class _ZoomableImageScreen extends StatefulWidget {
  const _ZoomableImageScreen({required this.image, required this.heroTag});

  final Widget image;
  final Object heroTag;

  @override
  State<_ZoomableImageScreen> createState() => _ZoomableImageScreenState();
}

class _ZoomableImageScreenState extends State<_ZoomableImageScreen>
    with SingleTickerProviderStateMixin {
  static const double _minScale = 1.0;
  static const double _maxScale = 5.0;
  static const double _doubleTapScale = 2.5;

  final TransformationController _controller = TransformationController();
  late final AnimationController _animationController;
  Animation<Matrix4>? _zoomAnimation;

  /// Смещение по вертикали при свайпе вниз для закрытия.
  ///
  /// Именно ValueNotifier, а не поле со setState: раньше каждый кадр жеста
  /// перестраивал весь экран вместе с InteractiveViewer и картинкой — отсюда
  /// и рывки. Теперь перерисовывается только то, что действительно движется.
  final ValueNotifier<double> _dragOffset = ValueNotifier<double>(0);

  /// Щипок в процессе. Нужен, чтобы отличить его от перетаскивания одним
  /// пальцем: возвращать картинку назад надо только после щипка.
  bool _pinching = false;

  /// Зум «залипший» — сделан двойным нажатием. Такой не сбрасывается:
  /// человек специально приблизил, чтобы рассмотреть.
  bool _stickyZoom = false;

  bool get _isZoomed => _controller.value.getMaxScaleOnAxis() > 1.01;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        final animation = _zoomAnimation;
        if (animation != null) _controller.value = animation.value;
      });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _controller.dispose();
    _dragOffset.dispose();
    super.dispose();
  }

  void _animateTo(Matrix4 target, {Curve curve = Curves.easeOutCubic}) {
    _zoomAnimation = Matrix4Tween(
      begin: _controller.value,
      end: target,
    ).animate(CurvedAnimation(parent: _animationController, curve: curve));
    _animationController.forward(from: 0);
  }

  /// Двойное нажатие: если увеличено — вернуть как было, иначе приблизить
  /// именно то место, куда нажали (а не центр картинки).
  void _handleDoubleTap(TapDownDetails details) {
    HapticFeedbackHelper.select();
    if (_isZoomed) {
      _stickyZoom = false;
      _animateTo(Matrix4.identity());
      return;
    }
    final position = details.localPosition;
    // Точка под пальцем должна остаться на месте: сдвигаем сцену так, чтобы
    // после масштабирования она попала туда же, где была до него.
    final target = Matrix4.identity()
      ..translateByDouble(
        -position.dx * (_doubleTapScale - 1),
        -position.dy * (_doubleTapScale - 1),
        0,
        1,
      )
      ..scaleByDouble(_doubleTapScale, _doubleTapScale, _doubleTapScale, 1);
    _stickyZoom = true;
    _animateTo(target);
  }

  void _handleInteractionUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount >= 2) _pinching = true;
  }

  void _handleInteractionEnd(ScaleEndDetails details) {
    if (!_pinching) return;
    _pinching = false;
    // Пальцы отпустили — картинка возвращается сама. Залипший зум от
    // двойного нажатия при этом не трогаем.
    if (!_stickyZoom && _isZoomed) {
      // Именно easeOutCubic: easeOutBack специально перелетает цель и
      // отыгрывает назад — на возврате это читается как рывок.
      _animateTo(Matrix4.identity());
    }
  }

  /// Кнопка-лупа: шаг увеличения. Дойдя до предела, возвращает в исходное —
  /// иначе из максимального зума нечем выйти, кроме жеста, о котором человек
  /// может не знать (кнопку он как раз и нажал потому, что жестами не хочет).
  static const double _zoomStep = 1.5;

  IconData get _zoomButtonIcon =>
      _atMaxZoom ? Icons.zoom_out_rounded : Icons.zoom_in_rounded;

  bool get _atMaxZoom =>
      _controller.value.getMaxScaleOnAxis() >= _maxScale - 0.01;

  void _handleZoomButton() {
    HapticFeedbackHelper.tap();
    if (_atMaxZoom) {
      _stickyZoom = false;
      _animateTo(Matrix4.identity());
      return;
    }

    final current = _controller.value.getMaxScaleOnAxis();
    final target = (current * _zoomStep).clamp(_minScale, _maxScale);
    final factor = target / current;
    // Увеличиваем от центра экрана: точки нажатия у кнопки нет, а от угла
    // картинка уехала бы в сторону.
    final size = context.size ?? Size.zero;
    final center = Offset(size.width / 2, size.height / 2);
    final matrix = Matrix4.copy(_controller.value)
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(factor, factor, factor, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);

    _stickyZoom = true;
    _animateTo(matrix);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_isZoomed) return;
    _dragOffset.value += details.delta.dy;
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_isZoomed) return;
    final velocity = details.velocity.pixelsPerSecond.dy;
    // Закрываем либо по резкому броску вниз, либо когда утащили достаточно
    // далеко — чтобы случайное дрожание пальца не выкидывало из просмотра.
    if (velocity > 700 || _dragOffset.value > 120) {
      Navigator.of(context).maybePop();
    } else {
      _dragOffset.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: _dragOffset,
      builder: (context, drag, child) {
        // Чем дальше утащили вниз, тем прозрачнее фон — видно, что жест
        // закроет просмотр.
        final progress = (drag.abs() / 300).clamp(0.0, 1.0);
        return ColoredBox(
          color: Colors.black.withValues(alpha: 1.0 - progress * 0.6),
          child: Opacity(
            opacity: 1.0 - progress * 0.35,
            child: Transform.translate(offset: Offset(0, drag), child: child),
          ),
        );
      },
      // Дерево картинки строится один раз и не перестраивается на жестах.
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              // Тап по фону закрывает — как в галерее телефона.
              onTap: () => Navigator.of(context).maybePop(),
              onDoubleTapDown: _handleDoubleTap,
              // Пустой обработчик обязателен: без него onDoubleTapDown
              // не сработает.
              onDoubleTap: () {},
              onVerticalDragUpdate: _handleDragUpdate,
              onVerticalDragEnd: _handleDragEnd,
              child: RepaintBoundary(
                child: InteractiveViewer(
                  transformationController: _controller,
                  minScale: _minScale,
                  maxScale: _maxScale,
                  onInteractionUpdate: _handleInteractionUpdate,
                  onInteractionEnd: _handleInteractionEnd,
                  // Без запаса по краям: с ним картинку можно было возить
                  // пальцем даже в неувеличенном виде — она «плавала», хотя
                  // двигать там нечего.
                  boundaryMargin: EdgeInsets.zero,
                  child: Center(
                    child: Hero(
                      tag: widget.heroTag,
                      // Дуговой полёт вместо прямой линии: движение читается
                      // живее, но остаётся коротким и не отвлекает.
                      createRectTween: (begin, end) =>
                          MaterialRectCenterArcTween(begin: begin, end: end),
                      child: widget.image,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Иконка лупы следит за самим контроллером, а не за setState:
          // на момент нажатия матрица ещё старая (анимация только стартует),
          // и значок отставал на шаг.
          ValueListenableBuilder<Matrix4>(
            valueListenable: _controller,
            builder: (context, _, _) => _ViewerButtons(
              zoomIcon: _zoomButtonIcon,
              onZoom: _handleZoomButton,
            ),
          ),
        ],
      ),
    );
  }
}

/// Кнопки просмотра — внизу справа, под большой палец.
///
/// Наверху крестик был неудобен: до верхнего угла телефона надо тянуться, а
/// просмотр закрывают часто. Белые круги с тёмными значками, потому что под
/// ними произвольная картинка: полупрозрачные тёмные кружки терялись на
/// тёмных снимках.
class _ViewerButtons extends StatelessWidget {
  const _ViewerButtons({required this.zoomIcon, required this.onZoom});

  final IconData zoomIcon;
  final VoidCallback onZoom;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 20,
      bottom: MediaQuery.of(context).padding.bottom + 24,
      child: Row(
        children: [
          _RoundButton(
            icon: zoomIcon,
            tooltip: appL10n.zoomIn,
            onTap: onZoom,
          ),
          const SizedBox(width: AppDimensions.spacingM),
          _RoundButton(
            icon: Icons.close_rounded,
            tooltip: appL10n.close,
            onTap: () {
              HapticFeedbackHelper.tap();
              Navigator.of(context).maybePop();
            },
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black54,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(icon, color: AppColors.primaryText, size: 26),
          ),
        ),
      ),
    );
  }
}

/// Подсказка «нажми, чтобы увеличить» — маленькая иконка лупы в углу картинки.
///
/// Без неё возможность зума остаётся незамеченной: пользователь из отзыва
/// пробовал «увеличить при просмотре» и решил, что функции просто нет.
class ZoomHintBadge extends StatelessWidget {
  const ZoomHintBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(
        Icons.zoom_in_rounded,
        size: 18,
        color: AppColors.cardBackground,
      ),
    );
  }
}
