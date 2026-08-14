import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/presentation/widgets/zoomable_image_viewer.dart';

/// Картинка вопроса из ассетов, устойчивая к разовым сбоям загрузки, с
/// скелетом-«шиммером» (бегущий блик) на время загрузки.
///
/// Зачем не голый [Image.asset]: в вебе ассет тянется по сети, и разовый сбой
/// (отменённый при свайпе PageView запрос, лимит одновременных соединений,
/// моргнувшая сеть) переводит виджет в состояние ошибки НАВСЕГДА — вместо
/// картинки остаётся заглушка, пока виджет не пересоздадут. Отсюда симптом:
/// «ушёл на другой вопрос, вернулся — картинка появилась».
///
/// Здесь ошибка не финальная: загрузка повторяется с нарастающей паузой
/// (повтор — сменой ключа [Image], упавшие загрузки Flutter в кеше не держит).
/// Пока картинка грузится или идёт повтор — показываем анимированный скелет
/// (понятно, что грузится). Только когда все попытки исчерпаны — статичный
/// серый прямоугольник (без «сломанной» иконки, которая сбивала с толку).
///
/// По нажатию картинка открывается на весь экран с зумом (см.
/// [showZoomableImage]) — детали на экзаменационных картинках мелкие, и без
/// увеличения их часто не разобрать.
class QuestionImage extends StatefulWidget {
  const QuestionImage({
    super.key,
    required this.assetPath,
    this.fit = BoxFit.cover,
    this.height = 200,
    this.maxAttempts = 3,
    this.zoomable = true,
  });

  final String assetPath;
  final BoxFit fit;

  /// Высота скелета-заглушки (пока картинка не загрузилась).
  final double height;

  /// Сколько всего попыток загрузки (первая + повторные).
  final int maxAttempts;

  /// Открывать ли картинку на весь экран по нажатию.
  final bool zoomable;

  @override
  State<QuestionImage> createState() => _QuestionImageState();
}

class _QuestionImageState extends State<QuestionImage> {
  int _attempt = 0;
  bool _givenUp = false;
  Timer? _retryTimer;

  @override
  void didUpdateWidget(QuestionImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath) {
      _retryTimer?.cancel();
      _attempt = 0;
      _givenUp = false;
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  void _scheduleRetry() {
    if (_retryTimer?.isActive ?? false) return;
    if (_attempt + 1 >= widget.maxAttempts) {
      if (mounted) setState(() => _givenUp = true);
      return;
    }
    // Пауза растёт (300ms, 600ms...): при отменённом или задавленном лимитом
    // соединения мгновенный повтор упёрся бы в то же самое.
    final delay = Duration(milliseconds: 300 * (_attempt + 1));
    _retryTimer = Timer(delay, () {
      if (mounted) setState(() => _attempt++);
    });
  }

  /// Открывает картинку на весь экран. В просмотрщик отдаём ту же картинку,
  /// но с [BoxFit.contain] — там она должна помещаться целиком, а не
  /// подрезаться под размер карточки.
  void _openFullScreen() {
    HapticFeedbackHelper.tap();
    showZoomableImage(
      context: context,
      heroTag: _heroTag,
      // filterQuality.medium: при увеличении в 5× картинка иначе рассыпается
      // на пиксельные ступеньки — а её открывают ровно затем, чтобы
      // рассмотреть мелкую деталь.
      image: Image.asset(
        widget.assetPath,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }

  /// Тег Hero обязан быть уникальным среди ВСЕХ живых виджетов маршрута.
  /// Тег из пути к файлу для этого не годится: экраны вопросов построены на
  /// [PageView], который держит в дереве и соседние страницы, а одна и та же
  /// картинка вполне может стоять у двух вопросов подряд — Flutter упал бы с
  /// «multiple heroes share the same tag». Поэтому тег привязан к экземпляру
  /// виджета, а не к содержимому.
  final Object _heroTag = UniqueKey();

  @override
  Widget build(BuildContext context) {
    // Попытки исчерпаны — статичный скелет (без анимации и «сломанной» иконки).
    if (_givenUp) {
      return _ImageSkeleton(height: widget.height, animate: false);
    }

    final image = Image.asset(
      widget.assetPath,
      // Ключ с номером попытки заставляет Flutter построить виджет заново,
      // а не переиспользовать залипший в ошибке элемент.
      key: ValueKey<String>('${widget.assetPath}#$_attempt'),
      fit: widget.fit,
      // Пока первый кадр не готов — анимированный скелет (идёт загрузка).
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return _ImageSkeleton(height: widget.height, animate: true);
      },
      errorBuilder: (_, _, _) {
        // Вызывается во время build — перестраивать состояние можно только
        // после того, как текущий кадр отрисован.
        WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleRetry());
        // Во время повторных попыток тоже «грузится», а не ошибка.
        return _ImageSkeleton(height: widget.height, animate: true);
      },
    );

    if (!widget.zoomable) return image;

    return GestureDetector(
      onTap: _openFullScreen,
      child: Stack(
        children: [
          // Hero оборачивает картинку в карточке, чтобы при открытии она
          // плавно «выросла» до полноэкранной, а не появилась рывком.
          Hero(tag: _heroTag, child: image),
          // Лупа в углу: без неё возможность зума незаметна — автор отзыва в
          // RuStore решил, что функции просто нет.
          const Positioned(
            right: 8,
            bottom: 8,
            child: ZoomHintBadge(),
          ),
        ],
      ),
    );
  }
}

/// Скелет-заглушка под картинку. [animate] true — бегущий блик (идёт загрузка),
/// false — статичный серый прямоугольник (попытки исчерпаны).
class _ImageSkeleton extends StatefulWidget {
  const _ImageSkeleton({required this.height, required this.animate});

  final double height;
  final bool animate;

  @override
  State<_ImageSkeleton> createState() => _ImageSkeletonState();
}

class _ImageSkeletonState extends State<_ImageSkeleton>
    with SingleTickerProviderStateMixin {
  static const Color _base = Color(0xFFE7E7EC);
  static const Color _highlight = Color(0xFFF5F5F8);
  // Один и тот же ключ у обоих состояний — чтобы «есть ли скелет» проверялось
  // единообразно (в т.ч. в тестах), независимо от анимации.
  static const Key _skeletonKey = ValueKey('question_image_skeleton');

  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1150),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return Container(
        key: _skeletonKey,
        height: widget.height,
        width: double.infinity,
        color: _base,
      );
    }

    return ClipRect(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return Container(
            key: _skeletonKey,
            height: widget.height,
            width: double.infinity,
            decoration: BoxDecoration(
              color: _base,
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: const [_base, _highlight, _base],
                stops: const [0.25, 0.5, 0.75],
                // Блик едет слева направо, зацикленно.
                transform:
                    _SlidingGradientTransform(controller.value * 2 - 1),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Сдвигает градиент по горизонтали — так «блик» скелета бежит по ширине.
class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform(this.slidePercent);

  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0, 0);
  }
}
