import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/support_chat_message.dart';
import 'package:pdd_app/data/services/support_chat_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/support/support_chat_screen.dart';
import 'package:pdd_app/presentation/widgets/support_chat_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _photo = SupportChatMessage(
  id: 'photo',
  text: 'Подпись к фотографии',
  imageUrl: 'https://support.test/photo.png',
  sender: SupportMessageSender.support,
  timestamp: 1000,
);
const _reply = SupportChatMessage(
  id: 'reply',
  text: 'Следующий ответ',
  sender: SupportMessageSender.support,
  timestamp: 2000,
);

class _ChatService extends Fake implements SupportChatService {
  List<SupportChatMessage> cached = [];
  List<SupportChatMessage> incoming = [_photo, _reply];
  List<SupportChatMessage> saved = [];
  int fetches = 0;
  bool fail = false;

  @override
  Future<List<SupportChatMessage>> loadCachedMessages() async => cached;

  @override
  Future<List<SupportChatMessage>?> tryFetchMessages({int? since}) async {
    fetches++;
    return fail ? null : incoming;
  }

  @override
  Future<void> saveCachedMessages(List<SupportChatMessage> messages) async {
    saved = List.of(messages);
  }
}

class _HttpClient extends Fake implements HttpClient {
  _HttpClient(this.response);
  final Future<HttpClientResponse> Function() response;
  int requests = 0;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requests++;
    return _HttpRequest(response());
  }
}

class _HttpRequest extends Fake implements HttpClientRequest {
  _HttpRequest(this.response);
  final Future<HttpClientResponse> response;

  @override
  Future<HttpClientResponse> close() => response;
}

class _HttpResponse extends Fake implements HttpClientResponse {
  _HttpResponse(this.bytes, {this.statusCode = HttpStatus.ok});
  final List<int> bytes;

  @override
  final int statusCode;

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

void main() {
  late Uint8List png;

  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(30, 60);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    png = data!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    updateAppLocale(const Locale('ru'));
  });

  Future<void> mount(WidgetTester tester, Widget screen) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      debugNetworkImageHttpClientProvider = null;
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      updateAppLocale(const Locale('ru'));
    });
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pump();
  }

  testWidgets(
    'failed reads back off, preserve history and recover on empty success',
    (tester) async {
      final service = _ChatService()
        ..cached = [_reply]
        ..incoming = []
        ..fail = true;
      await mount(tester, SupportChatScreen(service: service));
      expect(service.fetches, 1);
      expect(find.text(_reply.text), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 3500));
      expect(service.fetches, 1);
      await tester.pump(const Duration(milliseconds: 3500));
      expect(service.fetches, 2);
      await tester.pump(const Duration(seconds: 7));
      expect(service.fetches, 2);
      service.fail = false;
      await tester.pump(const Duration(milliseconds: 3500));
      expect(service.fetches, 3);
      await tester.pump(const Duration(milliseconds: 3500));
      expect(service.fetches, 4);
      expect(find.text(_reply.text), findsOneWidget);
    },
  );

  Future<void> waitForPhoto(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump();
      final images = tester.widgetList<RawImage>(
        find.descendant(
          of: find.byType(SupportChatImage),
          matching: find.byType(RawImage),
        ),
      );
      if (images.any((image) => image.image != null)) {
        debugNetworkImageHttpClientProvider = null;
        return;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    fail('The photo never became visible');
  }

  testWidgets('new replies appear in order only after the photo is decoded', (
    tester,
  ) async {
    final response = Completer<HttpClientResponse>();
    final client = _HttpClient(() => response.future);
    debugNetworkImageHttpClientProvider = () => client;
    final service = _ChatService();
    await mount(tester, SupportChatScreen(service: service));
    await tester.pump(const Duration(seconds: 2));
    expect(client.requests, 1);
    expect(find.text(_photo.text), findsNothing);
    expect(find.text(_reply.text), findsNothing);
    expect(service.saved, isEmpty);

    response.complete(_HttpResponse(png));
    await waitForPhoto(tester);
    expect(find.text(_photo.text), findsOneWidget);
    expect(find.text(_reply.text), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(service.saved.map((message) => message.id), ['photo', 'reply']);
    expect(client.requests, 1, reason: 'display reuses the precached image');
    expect(tester.takeException(), isNull);
  });

  testWidgets('slow photos reserve space and do not duplicate on polling', (
    tester,
  ) async {
    final response = Completer<HttpClientResponse>();
    final client = _HttpClient(() => response.future);
    debugNetworkImageHttpClientProvider = () => client;
    final service = _ChatService()..incoming = [];
    await mount(tester, SupportChatScreen(service: service));
    await tester.pump();
    service.incoming = [_photo, _reply];
    await tester.pump(const Duration(milliseconds: 3500));
    expect(service.fetches, 2);
    await tester.pump(const Duration(milliseconds: 3500));
    expect(service.fetches, 2, reason: 'the previous refresh is still active');
    expect(find.text(_photo.text), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.byType(SupportChatImage), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final reserved = tester.getSize(find.byType(SupportChatImage));
    expect(reserved.height, greaterThan(120));

    response.complete(_HttpResponse(png));
    await waitForPhoto(tester);
    expect(tester.getSize(find.byType(SupportChatImage)), reserved);
    await tester.pump(const Duration(milliseconds: 3500));
    await tester.pump();
    expect(find.text(_photo.text), findsOneWidget);
    expect(find.text(_reply.text), findsOneWidget);
    expect(client.requests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cached photos have a loading card and open only when ready', (
    tester,
  ) async {
    final response = Completer<HttpClientResponse>();
    debugNetworkImageHttpClientProvider = () =>
        _HttpClient(() => response.future);
    final service = _ChatService()
      ..cached = [_photo]
      ..incoming = [];
    await mount(tester, SupportChatScreen(service: service));
    await tester.pump();
    final reserved = tester.getSize(find.byType(SupportChatImage));
    expect(reserved.height, greaterThan(120));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(SupportChatImage));
    await tester.pump();
    expect(find.byType(InteractiveViewer), findsNothing);

    response.complete(_HttpResponse(png));
    await waitForPhoto(tester);
    expect(tester.getSize(find.byType(SupportChatImage)), reserved);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byType(SupportChatImage));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['ru', 'en', 'kk']) {
    testWidgets('photo load errors offer a working retry: $language', (
      tester,
    ) async {
      updateAppLocale(Locale(language));
      final client = _HttpClient(
        () async => _HttpResponse([], statusCode: 404),
      );
      debugNetworkImageHttpClientProvider = () => client;
      await mount(
        tester,
        Scaffold(
          body: SizedBox(
            width: 230,
            child: SupportChatImage(
              image: const NetworkImage('https://support.test/retry.png'),
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text(appL10n.supportChatImageLoadFailed), findsOneWidget);
      final reserved = tester.getSize(find.byType(SupportChatImage));
      debugNetworkImageHttpClientProvider = () =>
          _HttpClient(() async => _HttpResponse(png));
      await tester.tap(find.text(appL10n.supportChatRetry));
      await waitForPhoto(tester);
      expect(find.text(appL10n.supportChatImageLoadFailed), findsNothing);
      expect(tester.getSize(find.byType(SupportChatImage)), reserved);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('closing chat while a photo loads does not start a late timer', (
    tester,
  ) async {
    final response = Completer<HttpClientResponse>();
    debugNetworkImageHttpClientProvider = () =>
        _HttpClient(() => response.future);
    final service = _ChatService();
    await mount(tester, SupportChatScreen(service: service));
    await tester.pumpWidget(const SizedBox());
    response.complete(_HttpResponse(png));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(seconds: 10));
    expect(service.fetches, 1);
    expect(service.saved, isEmpty);
    debugNetworkImageHttpClientProvider = null;
    expect(tester.takeException(), isNull);
  });
}
