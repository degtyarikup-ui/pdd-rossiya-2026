import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/services/remote_notifications_service.dart';
import 'package:pdd_app/presentation/widgets/profile_notice_banner.dart';

import 'app_notice_banner_test.dart' show mockBannerImage;

AppNotice notice({
  String title = '',
  String body = '',
  String image = '',
  int? imageWidth,
  int? imageHeight,
  bool button = false,
}) => AppNotice(
  id: 'c069e042-5b7b-40a0-b15e-b80c4444ce1d',
  kind: 'profile',
  title: title,
  body: body,
  expiresAt: DateTime(2100),
  imageUrl: image,
  imageWidth: imageWidth,
  imageHeight: imageHeight,
  button: button,
  buttonText: 'Начать тренировку',
  action: NoticeAction.tickets,
);

void main() {
  Future<void> open(
    WidgetTester tester,
    AppNotice notice, {
    double width = 350,
    double scale = 1,
    bool dark = false,
    VoidCallback? onTap,
    VoidCallback? onDismiss,
    VoidCallback? onViewed,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(key: ValueKey('premium'), height: 110),
                    ProfileNoticeBanner(
                      notice: notice,
                      onTap: onTap ?? () {},
                      onDismiss: onDismiss ?? () {},
                      onViewed: onViewed,
                    ),
                    const SizedBox(key: ValueKey('following'), height: 120),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('tall loading image reserves space without recording a view', (
    tester,
  ) async {
    var views = 0;
    debugNetworkImageHttpClientProvider = () => _LoadingClient();
    await open(
      tester,
      notice(
        image: 'https://test.invalid/loading.png',
        imageWidth: 300,
        imageHeight: 1500,
        title: 'Текст под картинкой',
        button: true,
      ),
      onViewed: () => views++,
    );
    await tester.pump(const Duration(seconds: 2));
    expect(views, 0);
    expect(tester.getSize(find.byType(AspectRatio)).height, 1750);
    await tester.pumpWidget(const SizedBox());
    debugNetworkImageHttpClientProvider = null;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('all optional parts fit and following content stays below', (
    tester,
  ) async {
    await mockBannerImage(tester, width: 800, height: 400);
    for (final width in [280.0, 350.0, 600.0]) {
      for (final scale in [1.0, 2.0]) {
        for (var mask = 1; mask < 16; mask++) {
          await open(
            tester,
            notice(
              title: mask & 1 != 0 ? 'Новая тренировка в приложении' : '',
              body: mask & 2 != 0
                  ? 'Повторите сложные вопросы и проверьте свои знания.' * 5
                  : '',
              image: mask & 4 != 0 ? 'https://test.invalid/parts.png' : '',
              imageWidth: 800,
              imageHeight: 400,
              button: mask & 8 != 0,
            ),
            width: width,
            scale: scale,
            dark: width == 600,
          );
          final banner = tester.getRect(find.byType(ProfileNoticeBanner));
          final after = tester.getRect(find.byKey(const ValueKey('following')));
          expect(after.top, greaterThanOrEqualTo(banner.bottom));
          expect(banner.width, width);
          expect(
            tester.takeException(),
            isNull,
            reason: 'parts=$mask width=$width scale=$scale',
          );
          for (final element in find.byType(Text).evaluate()) {
            final rect = tester.getRect(find.byWidget(element.widget));
            expect(rect.left, greaterThanOrEqualTo(banner.left));
            expect(rect.right, lessThanOrEqualTo(banner.right));
            expect(rect.bottom, lessThanOrEqualTo(banner.bottom));
          }
        }
      }
    }
    debugNetworkImageHttpClientProvider = null;
  });

  testWidgets(
    'short and tall images keep their ratio and move the next block',
    (tester) async {
      for (final size in [const Size(1000, 180), const Size(300, 1500)]) {
        await mockBannerImage(
          tester,
          width: size.width.toInt(),
          height: size.height.toInt(),
        );
        await open(
          tester,
          notice(
            image: 'https://test.invalid/ratio-${size.height}.png',
            imageWidth: size.width.toInt(),
            imageHeight: size.height.toInt(),
          ),
        );
        for (
          var i = 0;
          i < 30 && find.byType(RawImage).evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        final banner = tester.getRect(find.byType(ProfileNoticeBanner));
        expect(banner.height, closeTo(350 * size.height / size.width, .01));
        expect(
          tester.widget<RawImage>(find.byType(RawImage)).fit,
          BoxFit.contain,
        );
        final after = tester.getRect(find.byKey(const ValueKey('following')));
        expect(after.top, closeTo(banner.bottom, .01));
        if (size.height > 1000) {
          await tester.drag(
            find.byType(SingleChildScrollView),
            const Offset(0, -1800),
          );
          await tester.pumpAndSettle();
          expect(
            tester.getRect(find.byKey(const ValueKey('following'))).top,
            lessThan(600),
          );
        }
        expect(tester.takeException(), isNull);
      }
      debugNetworkImageHttpClientProvider = null;
    },
  );

  testWidgets(
    'failed image-only collapses; text and action survive image error',
    (tester) async {
      await open(tester, notice(image: 'https://test.invalid/failure.png'));
      expect(tester.getSize(find.byType(ProfileNoticeBanner)).height, 0);
      expect(find.byIcon(Icons.close_rounded), findsNothing);
      await open(
        tester,
        notice(
          image: 'https://test.invalid/other-failure.png',
          title: 'Тренировка доступна',
          body: 'Продолжайте в удобное время.',
          button: true,
        ),
      );
      expect(find.text('Тренировка доступна'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(AspectRatio), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('button, card and dismiss have separate tap targets', (
    tester,
  ) async {
    var taps = 0;
    var dismisses = 0;
    await open(
      tester,
      notice(title: 'Обновление', body: 'Новые вопросы', button: true),
      onTap: () => taps++,
      onDismiss: () => dismisses++,
    );
    await tester.tap(find.text('Обновление'));
    expect(taps, 0);
    await tester.tap(find.byType(FilledButton));
    expect(taps, 1);
    await tester.tap(find.byIcon(Icons.close_rounded));
    expect(dismisses, 1);
    expect(taps, 1);
    await open(
      tester,
      notice(body: 'Вся карточка открывает билеты'),
      onTap: () => taps++,
      onDismiss: () => dismisses++,
    );
    await tester.tap(find.text('Вся карточка открывает билеты'));
    expect(taps, 2);
    await tester.tap(find.byIcon(Icons.close_rounded));
    expect(dismisses, 2);
    expect(taps, 2);
  });
}

class _LoadingClient extends Fake implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _LoadingRequest();
}

class _LoadingRequest extends Fake implements HttpClientRequest {
  @override
  Future<HttpClientResponse> close() => Completer<HttpClientResponse>().future;
}
