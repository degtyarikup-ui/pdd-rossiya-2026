import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/remote_notifications_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const id = 'c069e042-5b7b-40a0-b15e-b80c4444ce1a';
  Map<String, dynamic> notice({int? expiresAt}) => {
    'id': id,
    'title': 'Title',
    'body': 'Body',
    'expiresAt':
        expiresAt ??
        DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
  };
  final config = {
    'pushEnabled': false,
    'popupEnabled': true,
    'streakEnabled': true,
    'gameEnabled': true,
  };
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('message parsing rejects malformed payloads', () {
    expect(AppNotice.parse({'id': 'bad'}), isNull);
    expect(AppNotice.parse(notice()), isNotNull);
  });
  test('message shown once remains seen after app restart', () async {
    final client = MockClient((request) async {
      expect(request.url.queryParameters['app'], 'ru');
      expect(request.url.queryParameters['imageBanners'], '1');
      expect(request.url.queryParameters['imagePopups'], '1');
      expect(request.url.queryParameters['store'], 'play');
      return http.Response(
        jsonEncode({
          'config': config,
          'messages': [notice()],
        }),
        200,
      );
    });
    final service = RemoteNotificationsService.forTesting(client: client);
    await service.refresh();
    expect(service.nextNotice?.id, id);
    await service.markSeen(id);
    expect(service.nextNotice, isNull);
    final restarted = RemoteNotificationsService.forTesting(client: client);
    await restarted.refresh();
    expect(restarted.nextNotice, isNull);
  });
  test('expired campaigns and disabled popups are never displayed', () async {
    var disabled = false;
    final service = RemoteNotificationsService.forTesting(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'config': {...config, 'popupEnabled': !disabled},
            'messages': [notice(expiresAt: disabled ? null : 1)],
          }),
          200,
        ),
      ),
    );
    await service.refresh();
    expect(service.nextNotice, isNull);
    disabled = true;
    await service.refresh();
    expect(service.nextNotice, isNull);
  });
  test(
    'network failure clears visible campaigns but preserves cached policy',
    () async {
      var fail = false;
      final service = RemoteNotificationsService.forTesting(
        client: MockClient((_) async {
          if (fail) throw Exception('offline');
          return http.Response(
            jsonEncode({
              'config': {...config, 'streakEnabled': false},
              'messages': [notice()],
            }),
            200,
          );
        }),
      );
      await service.refresh();
      expect(service.nextNotice, isNotNull);
      fail = true;
      await service.refresh();
      expect(service.nextNotice, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(
          prefs.getString('notifications_ru_config')!,
        )['streakEnabled'],
        false,
      );
    },
  );
  test('simultaneous refreshes share one network request', () async {
    var requests = 0;
    final service = RemoteNotificationsService.forTesting(
      client: MockClient((_) async {
        requests++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return http.Response(
          jsonEncode({'config': config, 'messages': []}),
          200,
        );
      }),
    );
    await Future.wait([service.refresh(), service.refresh()]);
    expect(requests, 1);
  });

  test('rich notice fields are parsed; unsafe values are dropped', () {
    final n = AppNotice.parse({
      ...notice(),
      'kind': 'banner',
      'imageUrl': 'https://x.test/a.png',
      'accent': '#112233',
      'emoji': '🎉',
      'layout': 'cover',
      'action': 'tickets',
    })!;
    expect(n.isBanner, isTrue);
    expect(n.imageUrl, 'https://x.test/a.png');
    expect(n.accent?.toARGB32(), 0xFF112233);
    expect(n.layout, 'cover');
    expect(n.tap?.action, NoticeAction.tickets);
    final bad = AppNotice.parse({
      ...notice(),
      'imageUrl': 'http://x.test/a.png',
      'accent': 'red',
      'layout': 'weird',
      'action': 'url',
      'actionUrl': 'javascript:alert(1)',
    })!;
    expect(bad.imageUrl, isEmpty);
    expect(bad.accent, isNull);
    expect(bad.layout, 'standard');
    expect(bad.tap, isNull);
  });
  test('image-only banners accept empty text and a secure link', () {
    final banner = AppNotice.parse({
      ...notice(),
      'kind': 'banner',
      'layout': 'image',
      'title': '',
      'body': '',
      'imageUrl': 'https://x.test/banner.png',
      'action': 'url',
      'actionUrl': 'https://pdd-drive.ru/blog/',
    })!;
    expect(banner.isBanner, isTrue);
    expect(banner.isImageBanner, isTrue);
    expect(banner.layout, 'image');
    expect(banner.title, isEmpty);
    expect(banner.body, isEmpty);
    expect(banner.imageUrl, 'https://x.test/banner.png');
    expect(banner.tap?.action, NoticeAction.url);
    expect(banner.tap?.url, 'https://pdd-drive.ru/blog/');
  });
  test('image layout requires a secure image', () {
    final imageBanner = {
      ...notice(),
      'kind': 'banner',
      'layout': 'image',
      'imageUrl': 'https://x.test/banner.png',
    };
    expect(AppNotice.parse({...imageBanner, 'imageUrl': ''}), isNull);
    expect(
      AppNotice.parse({...imageBanner, 'imageUrl': 'http://x.test/banner.png'}),
      isNull,
    );
    final popup = AppNotice.parse({...imageBanner, 'kind': 'popup'})!;
    expect(popup.isImageOnly, isTrue);
    expect(popup.isBanner, isFalse);
    expect(popup.button, isFalse);
    expect(
      AppNotice.parse({...notice(), 'kind': 'banner'})?.isImageBanner,
      isFalse,
    );
  });
  test('the button is optional; legacy notices keep it', () {
    expect(AppNotice.parse(notice())!.button, isTrue);
    final plain = AppNotice.parse({...notice(), 'body': '', 'button': false})!;
    expect(plain.button, isFalse);
    expect(plain.body, isEmpty);
  });
  test('banners are separate from popups and stay dismissed', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'config': config,
          'messages': [
            {...notice(), 'kind': 'banner'},
          ],
        }),
        200,
      ),
    );
    final service = RemoteNotificationsService.forTesting(client: client);
    await service.refresh();
    expect(service.nextNotice, isNull);
    expect(service.banners.value.single.id, id);
    await service.dismissBanner(id);
    expect(service.banners.value, isEmpty);
    await service.refresh();
    expect(service.banners.value, isEmpty);
  });
  test('dismissed image banner remains hidden after app restart', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'config': config,
          'messages': [
            {
              ...notice(),
              'kind': 'banner',
              'layout': 'image',
              'title': '',
              'body': '',
              'imageUrl': 'https://x.test/banner.png',
            },
          ],
        }),
        200,
      ),
    );
    final service = RemoteNotificationsService.forTesting(client: client);
    await service.refresh();
    expect(service.banners.value.single.isImageBanner, isTrue);
    expect(service.nextNotice, isNull);
    await service.dismissBanner(id);
    expect(service.banners.value, isEmpty);

    final restarted = RemoteNotificationsService.forTesting(client: client);
    await restarted.refresh();
    expect(restarted.banners.value, isEmpty);
    expect(restarted.nextNotice, isNull);
  });
  test(
    'personal identity is never sent in notification query parameters',
    () async {
      Uri? requested;
      final service = RemoteNotificationsService.forTesting(
        client: MockClient((request) async {
          requested = request.url;
          return http.Response(
            jsonEncode({
              'config': config,
              'messages': [notice()],
            }),
            200,
          );
        }),
        userProvider: () => UserProfile(
          id: 'google_123',
          name: 'Sergei',
          email: 'admin@test.ru',
          provider: AuthProviderType.google,
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      await service.refresh();
      expect(requested?.queryParameters.containsKey('userId'), isFalse);
      expect(requested?.queryParameters.containsKey('email'), isFalse);
      expect(requested.toString(), isNot(contains('admin')));
    },
  );

  test(
    'a campaign also sent as a push shows no window or banner where the push arrived',
    () async {
      const bannerId = 'c069e042-5b7b-40a0-b15e-b80c4444ce1b';
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'config': config,
            'messages': [
              {...notice(), 'kind': 'popup', 'push': true},
              {...notice(), 'id': bannerId, 'kind': 'banner', 'push': true},
            ],
          }),
          200,
        ),
      );
      final pushed = RemoteNotificationsService.forTesting(
        client: client,
        receivesPush: true,
      );
      await pushed.refresh();
      expect(pushed.nextNotice, isNull);
      expect(pushed.banners.value, isEmpty);
      expect(pushed.inbox.value, hasLength(2), reason: 'still in the inbox');

      SharedPreferences.setMockInitialValues({});
      final withoutPush = RemoteNotificationsService.forTesting(
        client: client,
        receivesPush: false,
      );
      await withoutPush.refresh();
      expect(withoutPush.nextNotice?.id, id);
      expect(withoutPush.banners.value.single.id, bannerId);
    },
  );
  test('a picture alone is a valid inbox entry', () {
    final news = AppNotice.parse({
      ...notice(),
      'kind': 'news',
      'title': '',
      'body': '',
      'layout': 'image',
      'imageUrl': 'https://cdn.test/n.png',
    })!;
    expect(news.isNews && news.isImageOnly, isTrue);
    expect(news.push, isFalse);
  });
}
