import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Рендерит виджет в PNG, не показывая его на экране.
///
/// Обычный рецепт «обернуть в RepaintBoundary и дождаться кадра» здесь не
/// годится: карточка 1080×1080 не помещается на экран телефона, а показывать
/// её пользователю и не нужно. Поэтому строим отдельное дерево рендеринга
/// через [PipelineOwner] + [BuildOwner] и прогоняем его вручную — виджет
/// живёт ровно столько, сколько нужно для снимка.
class ShareCardRenderer {
  ShareCardRenderer._();

  /// Собирает [widget] размером [size] в PNG.
  ///
  /// Возвращает null, если что-то пошло не так: шеринг картинкой —
  /// необязательная надстройка, и ронять из-за неё экран результата нельзя
  /// (вызывающий код откатывается на отправку обычным текстом).
  static Future<Uint8List?> renderToPng({
    required Widget widget,
    required Size size,
    double pixelRatio = 1.0,
  }) async {
    try {
      final repaintBoundary = RenderRepaintBoundary();

      final renderView = RenderView(
        view: ui.PlatformDispatcher.instance.views.first,
        child: RenderPositionedBox(
          alignment: Alignment.center,
          child: repaintBoundary,
        ),
        configuration: ViewConfiguration(
          logicalConstraints: BoxConstraints.tight(size),
          devicePixelRatio: pixelRatio,
        ),
      );

      final pipelineOwner = PipelineOwner()..rootNode = renderView;
      renderView.prepareInitialFrame();

      final buildOwner = BuildOwner(focusManager: FocusManager());
      final rootElement = RenderObjectToWidgetAdapter<RenderBox>(
        container: repaintBoundary,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            // Пользовательский масштаб шрифта не должен ломать вёрстку
            // карточки: она рендерится в файл фиксированного размера.
            data: const MediaQueryData(textScaler: TextScaler.noScaling),
            child: widget,
          ),
        ),
      ).attachToRenderTree(buildOwner);

      buildOwner
        ..buildScope(rootElement)
        ..finalizeTree();
      pipelineOwner
        ..flushLayout()
        ..flushCompositingBits()
        ..flushPaint();

      final image = await repaintBoundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      return byteData?.buffer.asUint8List();
    } catch (e, s) {
      // Молча откатываемся на текстовый шеринг, но в отладке след оставляем.
      debugPrint('ShareCardRenderer: не удалось собрать картинку: $e\n$s');
      return null;
    }
  }
}
