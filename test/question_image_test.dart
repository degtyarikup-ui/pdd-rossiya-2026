import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/presentation/widgets/question_image.dart';
import 'package:pdd_app/presentation/widgets/zoomable_image_viewer.dart';

/// Бандл, у которого загрузка ассета падает заданное число раз, а потом
/// отдаёт валидный PNG — имитация разового сетевого сбоя в вебе.
///
/// Важно: [AssetImage] перед самой картинкой читает через бандл манифест
/// ассетов, поэтому манифест здесь отдаётся всегда (пустой), а «ломается»
/// только запрошенная картинка — иначе тест проверял бы сбой манифеста.
class _FlakyAssetBundle extends CachingAssetBundle {
  _FlakyAssetBundle({required this.failures, required this.pngBytes});

  final int failures;
  final Uint8List pngBytes;
  int imageLoadCalls = 0;

  static final ByteData _emptyManifest =
      const StandardMessageCodec().encodeMessage(<String, Object>{})!;

  @override
  Future<ByteData> load(String key) async {
    if (key.startsWith('AssetManifest')) return _emptyManifest;

    imageLoadCalls++;
    if (imageLoadCalls <= failures) {
      throw FlutterError('simulated transient asset failure #$imageLoadCalls');
    }
    return ByteData.view(pngBytes.buffer);
  }
}

/// Минимальный валидный PNG 1×1, чтобы декодер отработал по-настоящему.
Future<Uint8List> _onePixelPng() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 1, 1),
    Paint()..color = const Color(0xFF00FF00),
  );
  final image = await recorder.endRecording().toImage(1, 1);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Widget _host(Widget child, AssetBundle bundle) {
  return MaterialApp(
    // Бандл подставляем через builder, а не только в home: полноэкранный
    // просмотр картинки открывается ОТДЕЛЬНЫМ маршрутом, и обёртка внутри
    // home на него бы не распространилась — картинка там пошла бы в
    // настоящий бандл и не загрузилась.
    builder: (context, child) =>
        DefaultAssetBundle(bundle: bundle, child: child!),
    home: Scaffold(body: child),
  );
}

void main() {
  late Uint8List png;

  setUpAll(() async => png = await _onePixelPng());

  const skeletonKey = ValueKey('question_image_skeleton');

  testWidgets(
    'разовый сбой загрузки не оставляет заглушку навсегда — картинка догружается',
    (tester) async {
      final bundle = _FlakyAssetBundle(failures: 1, pngBytes: png);

      await tester.pumpWidget(
        _host(const QuestionImage(assetPath: 'a/b/q.jpg'), bundle),
      );
      await tester.pump();

      // Первая попытка провалилась — на экране скелет (грузится), не картинка.
      expect(find.byKey(skeletonKey), findsOneWidget);

      // Ретрай с нарастающей паузой запускает новую загрузку (успешную).
      await tester.pump(const Duration(milliseconds: 400));
      // Даём реальному декодеру картинки доработать (не pumpAndSettle —
      // анимация скелета бесконечная и не даёт ему завершиться).
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();

      expect(bundle.imageLoadCalls, greaterThan(1),
          reason: 'повторная загрузка должна была произойти');
      expect(
        find.byKey(skeletonKey),
        findsNothing,
        reason: 'после успешного повтора скелета быть не должно',
      );
    },
  );

  testWidgets(
    'когда попытки исчерпаны — статичный скелет и ретраи не крутятся вечно',
    (tester) async {
      final bundle = _FlakyAssetBundle(failures: 99, pngBytes: png);

      await tester.pumpWidget(
        _host(
          const QuestionImage(assetPath: 'a/b/q.jpg', maxAttempts: 3),
          bundle,
        ),
      );
      await tester.pump();
      // Пауза с запасом на все ретраи (300ms + 600ms) — доходим до give-up.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      // Показан статичный скелет (без анимации — попытки исчерпаны).
      expect(find.byKey(skeletonKey), findsOneWidget);
      expect(
        bundle.imageLoadCalls,
        lessThanOrEqualTo(3),
        reason: 'ретраи должны останавливаться на maxAttempts',
      );
    },
  );

  // --- Просмотр картинки с увеличением -----------------------------------
  // Повод: отзыв в RuStore «Картинки не увеличиваются при просмотре».

  testWidgets('нажатие на картинку открывает полноэкранный просмотр с зумом',
      (tester) async {
    final bundle = _FlakyAssetBundle(failures: 0, pngBytes: png);

    await tester.pumpWidget(
      _host(const QuestionImage(assetPath: 'a/b/q.jpg'), bundle),
    );
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    // До нажатия просмотрщика нет, но подсказка-лупа видна: без неё
    // пользователь не догадается, что картинку можно увеличить.
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.byType(ZoomHintBadge), findsOneWidget);

    await tester.tap(find.byType(QuestionImage));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Открылся просмотрщик: InteractiveViewer даёт щипок-зум и перетаскивание.
    expect(find.byType(InteractiveViewer), findsOneWidget);

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.maxScale, greaterThanOrEqualTo(3.0),
        reason: 'запаса увеличения должно хватать, чтобы рассмотреть детали');
    expect(viewer.minScale, 1.0);
  });

  testWidgets('zoomable: false оставляет картинку без просмотрщика и лупы',
      (tester) async {
    final bundle = _FlakyAssetBundle(failures: 0, pngBytes: png);

    await tester.pumpWidget(
      _host(
        const QuestionImage(assetPath: 'a/b/q.jpg', zoomable: false),
        bundle,
      ),
    );
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    expect(find.byType(ZoomHintBadge), findsNothing);

    await tester.tap(find.byType(QuestionImage));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets(
    'у двух картинок с ОДНИМ путём разные теги Hero',
    (tester) async {
      // Регрессия: экраны вопросов построены на PageView, который держит в
      // дереве и соседние страницы. Если у двух вопросов подряд одна и та же
      // картинка, тег Hero, собранный из пути к файлу, дал бы падение
      // «multiple heroes share the same tag». Поэтому тег привязан к
      // экземпляру виджета — этот тест и стережёт это свойство.
      final bundle = _FlakyAssetBundle(failures: 0, pngBytes: png);

      await tester.pumpWidget(
        _host(
          const Column(
            children: [
              SizedBox(
                width: 200,
                height: 100,
                child: QuestionImage(assetPath: 'a/b/q.jpg'),
              ),
              SizedBox(
                width: 200,
                height: 100,
                child: QuestionImage(assetPath: 'a/b/q.jpg'),
              ),
            ],
          ),
          bundle,
        ),
      );
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();

      final tags = tester
          .widgetList<Hero>(find.byType(Hero))
          .map((h) => h.tag)
          .toList();

      expect(tags, hasLength(2));
      expect(
        tags.first,
        isNot(equals(tags.last)),
        reason: 'одинаковые теги уронили бы Hero при открытии просмотра',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
