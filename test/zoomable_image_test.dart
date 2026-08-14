import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/presentation/widgets/zoomable_image_viewer.dart';

/// Полноэкранный просмотр картинки.
///
/// Проверяем поведение жестов: они молча ломаются при любой правке разметки,
/// а увидеть это можно только руками на устройстве.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> openViewer(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showZoomableImage(
                  context: context,
                  heroTag: 'tag',
                  image: Container(
                    width: 200,
                    height: 200,
                    color: AppColors.accent,
                  ),
                ),
                child: const Text('открыть'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('открыть'));
    await tester.pumpAndSettle();
  }

  InteractiveViewer viewerOf(WidgetTester tester) =>
      tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));

  double scaleOf(WidgetTester tester) => viewerOf(tester)
      .transformationController!
      .value
      .getMaxScaleOnAxis();

  testWidgets('кнопка закрытия — внизу справа, белая с тёмным крестиком',
      (tester) async {
    await openViewer(tester);

    final positioned = tester.widget<Positioned>(
      find.ancestor(
        of: find.byIcon(Icons.close_rounded),
        matching: find.byType(Positioned),
      ),
    );
    // Внизу справа: до верхнего угла телефона надо тянуться, а просмотр
    // закрывают часто.
    expect(positioned.bottom, isNotNull);
    expect(positioned.right, isNotNull);
    expect(positioned.top, isNull);

    final material = tester.widget<Material>(
      find.ancestor(
        of: find.byIcon(Icons.close_rounded),
        matching: find.byType(Material),
      ).first,
    );
    // Белый круг с тёмным крестиком: под кнопкой произвольная картинка, и
    // полупрозрачный тёмный кружок терялся на тёмных снимках.
    expect(material.color, AppColors.white);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.close_rounded)).color,
      AppColors.primaryText,
    );
  });

  testWidgets('щипок увеличивает, а после отпускания картинка возвращается',
      (tester) async {
    await openViewer(tester);
    expect(scaleOf(tester), closeTo(1.0, 0.01));

    final center = tester.getCenter(find.byType(InteractiveViewer));
    final p1 = await tester.startGesture(center - const Offset(20, 0));
    final p2 = await tester.startGesture(center + const Offset(20, 0));
    await tester.pump();

    // Разводим пальцы — картинка увеличивается.
    await p1.moveBy(const Offset(-80, 0));
    await p2.moveBy(const Offset(80, 0));
    await tester.pump();
    expect(scaleOf(tester), greaterThan(1.5));

    // Отпускаем — возвращается сама, как в ленте Instagram.
    await p1.up();
    await p2.up();
    await tester.pumpAndSettle();
    expect(
      scaleOf(tester),
      closeTo(1.0, 0.01),
      reason: 'после щипка картинка обязана вернуться в исходное',
    );
  });

  testWidgets('зум двойным нажатием остаётся — им рассматривают деталь',
      (tester) async {
    await openViewer(tester);

    final center = tester.getCenter(find.byType(InteractiveViewer));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pumpAndSettle();

    expect(
      scaleOf(tester),
      greaterThan(2.0),
      reason: 'иначе деталь нельзя спокойно разглядеть — а ради этого '
          'просмотр и открывают',
    );
  });

  testWidgets('кнопка-лупа приближает примерно в 1,5 раза и не отпружинивает',
      (tester) async {
    await openViewer(tester);

    await tester.tap(find.byIcon(Icons.zoom_in_rounded));
    await tester.pumpAndSettle();

    expect(scaleOf(tester), closeTo(1.5, 0.05));

    // Зум кнопкой — «залипающий», как двойное нажатие: им пришли
    // рассматривать, а не подсмотреть.
    await tester.pump(const Duration(seconds: 1));
    expect(scaleOf(tester), closeTo(1.5, 0.05));
  });

  testWidgets('на предельном увеличении лупа возвращает в исходное',
      (tester) async {
    await openViewer(tester);

    // 1.5^4 ≈ 5.06 — упираемся в предел за четыре нажатия.
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byIcon(Icons.zoom_in_rounded));
      await tester.pumpAndSettle();
    }
    expect(find.byIcon(Icons.zoom_out_rounded), findsOneWidget,
        reason: 'иначе из предельного зума нечем выйти кнопкой');

    await tester.tap(find.byIcon(Icons.zoom_out_rounded));
    await tester.pumpAndSettle();
    expect(scaleOf(tester), closeTo(1.0, 0.01));
  });
}
