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
  test('signed-in user passes userId and email for personal test campaigns', () async {
    Uri? requested;
    final service = RemoteNotificationsService.forTesting(
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode({'config': config, 'messages': [notice()]}),
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
    expect(requested?.queryParameters['userId'], 'google_123');
    expect(requested?.queryParameters['email'], 'admin@test.ru');
    expect(
      RemoteNotificationsService.userTopic('  Admin@Test.ru '),
      'pdd_u_61646d696e40746573742e7275',
    );
  });
}
