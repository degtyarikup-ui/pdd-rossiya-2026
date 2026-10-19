import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/services/remote_notifications_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/app_notice_widgets.dart';
import 'package:pdd_app/presentation/widgets/progress_panel_card.dart';

void main() {
  const emptyStats = {
    'correctAnswers': 0,
    'answeredQuestions': 0,
    'passedTickets': 0,
    'wrongQuestions': 0,
    'totalQuestions': 800,
    'totalTickets': 40,
  };

  Widget buildBannerBox({
    required double width,
    double textScale = 1.0,
    TargetPlatform platform = TargetPlatform.android,
    required AppNotice notice,
    required VoidCallback onTap,
    required VoidCallback onDismiss,
    Widget? imageFallback,
  }) {
    return MaterialApp(
      theme: ThemeData(platform: platform),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 800),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: AppNoticeBannerSlot(
                notice: notice,
                statistics:
                    imageFallback ?? const ProgressPanelCard(stats: emptyStats),
                onTap: onTap,
                onDismiss: onDismiss,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'AppNoticeBanner with max 200 char body and 1.6x text scale does not overflow',
    (tester) async {
      final notice = AppNotice(
        id: 'c069e042-5b7b-40a0-b15e-b80c4444ce1d',
        title: 'Большое обновление билетов 2026 года с комментариями ГИБДД',
        body:
            'В приложение добавлены новые комментарии к каждому билету категории AB и CD. Учите правила комфортно, следите за своей серией дней и успешно сдавайте теоретический экзамен с первой попытки!',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
        kind: 'banner',
        buttonText: 'Узнать больше и начать',
        action: NoticeAction.tickets,
      );

      await tester.pumpWidget(
        buildBannerBox(
          width: 320,
          textScale: 1.6,
          notice: notice,
          onTap: () {},
          onDismiss: () {},
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'image keeps its proportions across platforms, widths and fonts',
    (tester) async {
      final notice = AppNotice(
        id: 'c069e042-5b7b-40a0-b15e-b80c4444ce1d',
        title: '',
        body: '',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
        kind: 'banner',
        layout: 'image',
        imageUrl: 'https://x.test/banner.png',
      );

      await mockBannerImage(tester);
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        for (final textScale in [1.0, 1.6, 2.0]) {
          for (final width in [320.0, 350.0, 374.0, 390.0, 600.0]) {
            await tester.pumpWidget(
              buildBannerBox(
                width: width,
                textScale: textScale,
                platform: platform,
                notice: notice,
                onTap: () {},
                onDismiss: () {},
              ),
            );
            await waitForBannerImage(tester);

            final image = tester.widget<Image>(find.byType(Image));
            final bannerRect = tester.getRect(find.byType(AppNoticeBanner));
            final imageRect = tester.getRect(find.byType(Image));
            expect(image.image, isA<NetworkImage>());
            expect((image.image as NetworkImage).url, notice.imageUrl);
            expect(image.fit, BoxFit.contain);
            expect(imageRect.width, bannerRect.width);
            expect(imageRect.left, bannerRect.left);
            expect(bannerRect.width, width);
            expect(bannerRect.height, closeTo(width * 734 / 1920, 0.001));
            expect(tester.getRect(find.byType(RawImage)), bannerRect);
            expect(find.byType(ProgressPanelCard), findsNothing);
            expect(find.byIcon(Icons.close_rounded), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
        }
      }
    },
  );

  testWidgets('other image proportions also determine the slot height', (
    tester,
  ) async {
    for (final size in [const Size(1600, 900), const Size(800, 800)]) {
      await mockBannerImage(
        tester,
        width: size.width.toInt(),
        height: size.height.toInt(),
      );
      final notice = AppNotice(
        id: 'other-proportions',
        title: '',
        body: '',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
        kind: 'banner',
        layout: 'image',
        imageUrl: 'https://x.test/banner-${size.width}.png',
      );
      await tester.pumpWidget(
        buildBannerBox(
          width: 350,
          notice: notice,
          onTap: () {},
          onDismiss: () {},
        ),
      );
      await waitForBannerImage(tester);
      expect(
        tester.getSize(find.byType(AppNoticeBanner)),
        Size(350, 350 / size.aspectRatio),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('image tap and close have separate actions', (tester) async {
    await mockBannerImage(tester);
    var opened = 0;
    var dismissed = 0;
    final notice = AppNotice(
      id: 'c069e042-5b7b-40a0-b15e-b80c4444ce1d',
      title: '',
      body: '',
      expiresAt: DateTime.now().add(const Duration(days: 1)),
      kind: 'banner',
      layout: 'image',
      imageUrl: 'https://x.test/banner.png',
      action: NoticeAction.url,
      actionUrl: 'https://pdd-drive.ru/blog/',
    );
    await tester.pumpWidget(
      buildBannerBox(
        width: 360,
        notice: notice,
        onTap: () => opened++,
        onDismiss: () => dismissed++,
      ),
    );
    await waitForBannerImage(tester);

    await tester.tap(find.byType(Image));
    expect(opened, 1);
    expect(dismissed, 0);

    await tester.tap(find.byIcon(Icons.close_rounded));
    expect(opened, 1);
    expect(dismissed, 1);
  });

  testWidgets('loaded image replaces statistics and enables banner actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final imageBytes = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(1920, 734);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      return data!.buffer.asUint8List();
    });
    final response = Completer<HttpClientResponse>();
    debugNetworkImageHttpClientProvider = () =>
        _BannerHttpClient(response.future);
    addTearDown(() {
      debugNetworkImageHttpClientProvider = null;
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });
    var opened = 0;
    var dismissed = 0;
    final notice = AppNotice(
      id: 'c069e042-5b7b-40a0-b15e-b80c4444ce1d',
      title: '',
      body: '',
      expiresAt: DateTime.now().add(const Duration(days: 1)),
      kind: 'banner',
      layout: 'image',
      imageUrl: 'https://x.test/loaded-wide-banner.png',
      action: NoticeAction.url,
      actionUrl: 'https://pdd-drive.ru/blog/',
    );
    await tester.pumpWidget(
      buildBannerBox(
        width: 360,
        notice: notice,
        onTap: () => opened++,
        onDismiss: () => dismissed++,
        imageFallback: const Center(child: Text('Statistics fallback')),
      ),
    );
    expect(find.text('Statistics fallback'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNothing);

    response.complete(_BannerHttpResponse(imageBytes!));
    for (var i = 0; i < 20 && find.byType(RawImage).evaluate().isEmpty; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    await tester.pumpAndSettle();
    debugNetworkImageHttpClientProvider = null;

    expect(find.text('Statistics fallback'), findsNothing);
    final image = tester.widget<RawImage>(find.byType(RawImage));
    expect(image.image?.width, 1920);
    expect(image.image?.height, 734);
    expect(image.fit, BoxFit.contain);
    expect(
      tester.getSize(find.byType(RawImage)).width,
      tester.getSize(find.byType(AppNoticeBanner)).width,
    );
    final bannerActionNodes = tester.semantics
        .simulatedAccessibilityTraversal()
        .where(
          (node) =>
              node.getSemanticsData().label == appL10n.noticeImageBanner &&
              node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
        )
        .toList();
    expect(bannerActionNodes, hasLength(1));
    final closeLabel = MaterialLocalizations.of(
      tester.element(find.byType(AppNoticeBanner)),
    ).closeButtonTooltip;
    final closeNodes = tester.semantics
        .simulatedAccessibilityTraversal()
        .where(
          (node) =>
              node.getSemanticsData().tooltip == closeLabel &&
              node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
        )
        .toList();
    expect(closeNodes, hasLength(1));
    final closeNode = closeNodes.single;
    expect(
      closeNode.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      isTrue,
    );
    expect(closeNode.id, isNot(bannerActionNodes.single.id));
    semantics.dispose();
    await tester.tapAt(tester.getCenter(find.byType(AppNoticeBanner)));
    expect(opened, 1);
    expect(dismissed, 0);
    await tester.tap(find.byIcon(Icons.close_rounded));
    expect(opened, 1);
    expect(dismissed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('image without an action is still dismissible', (tester) async {
    await mockBannerImage(tester);
    var opened = 0;
    var dismissed = 0;
    final notice = AppNotice(
      id: 'c069e042-5b7b-40a0-b15e-b80c4444ce1d',
      title: '',
      body: '',
      expiresAt: DateTime.now().add(const Duration(days: 1)),
      kind: 'banner',
      layout: 'image',
      imageUrl: 'https://x.test/banner.png',
    );
    await tester.pumpWidget(
      buildBannerBox(
        width: 360,
        notice: notice,
        onTap: () => opened++,
        onDismiss: () => dismissed++,
      ),
    );
    await waitForBannerImage(tester);

    await tester.tap(find.byType(Image));
    expect(opened, 0);
    await tester.tap(find.byIcon(Icons.close_rounded));
    expect(opened, 0);
    expect(dismissed, 1);
  });

  testWidgets('loading or failed image keeps statistics without banner actions', (
    tester,
  ) async {
    var opened = 0;
    var dismissed = 0;
    final notice = AppNotice(
      id: 'c069e042-5b7b-40a0-b15e-b80c4444ce1d',
      title: '',
      body: '',
      expiresAt: DateTime.now().add(const Duration(days: 1)),
      kind: 'banner',
      layout: 'image',
      imageUrl: 'https://x.test/unavailable.png',
      action: NoticeAction.url,
      actionUrl: 'https://pdd-drive.ru/blog/',
    );
    await tester.pumpWidget(
      buildBannerBox(
        width: 360,
        notice: notice,
        onTap: () => opened++,
        onDismiss: () => dismissed++,
        imageFallback: const Center(child: Text('Statistics fallback')),
      ),
    );
    expect(find.text('Statistics fallback'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNothing);

    // Widget tests return HTTP 400 for network images, exercising load failure.
    await tester.pumpAndSettle();
    expect(find.text('Statistics fallback'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    await tester.tap(find.text('Statistics fallback'));
    expect(opened, 0);
    expect(dismissed, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy emoji is not shown in banners or dialogs', (
    tester,
  ) async {
    final notice = AppNotice(
      id: 'c069e042-5b7b-40a0-b15e-b80c4444ce1d',
      title: 'Обновление',
      body: 'Новые вопросы уже доступны',
      expiresAt: DateTime.now().add(const Duration(days: 1)),
      kind: 'banner',
      emoji: '🎉',
    );
    await tester.pumpWidget(
      buildBannerBox(
        width: 360,
        notice: notice,
        onTap: () {},
        onDismiss: () {},
      ),
    );
    expect(find.textContaining('🎉'), findsNothing);
    expect(find.textContaining('🔔'), findsNothing);
    expect(find.text(notice.title), findsOneWidget);
    expect(find.text(notice.body), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AppNoticeDialog(notice: notice)),
      ),
    );
    expect(find.textContaining('🎉'), findsNothing);
    expect(find.textContaining('🔔'), findsNothing);
    expect(find.text(notice.title), findsOneWidget);
    expect(find.text(notice.body), findsOneWidget);
  });
}

class _BannerHttpClient extends Fake implements HttpClient {
  _BannerHttpClient(this.response);
  final Future<HttpClientResponse> response;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _BannerHttpRequest(response);
}

class _BannerHttpRequest extends Fake implements HttpClientRequest {
  _BannerHttpRequest(this.response);
  final Future<HttpClientResponse> response;

  @override
  Future<HttpClientResponse> close() => response;
}

class _BannerHttpResponse extends Fake implements HttpClientResponse {
  _BannerHttpResponse(this.bytes);
  final List<int> bytes;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => bytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

Future<void> mockBannerImage(
  WidgetTester tester, {
  int width = 1920,
  int height = 734,
}) async {
  final bytes = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.orange, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return data!.buffer.asUint8List();
  });
  debugNetworkImageHttpClientProvider = () =>
      _BannerHttpClient(Future.value(_BannerHttpResponse(bytes!)));
  addTearDown(() {
    debugNetworkImageHttpClientProvider = null;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
}

Future<void> waitForBannerImage(WidgetTester tester) async {
  for (var i = 0; i < 30 && find.byType(RawImage).evaluate().isEmpty; i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.pumpAndSettle();
  expect(find.byType(RawImage), findsOneWidget);
  debugNetworkImageHttpClientProvider = null;
}
