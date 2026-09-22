import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final auth = AuthService.instance;
  final premium = PremiumService.instance;
  final expiry = DateTime.now().toUtc().add(const Duration(days: 2));
  Future<bool> verify() => premium.recordPurchase(
    tier: PremiumTier.weekly,
    price: 'test',
    store: 'googleplay',
    productId: 'ru.pdd.pddapp.premium.week',
    purchaseToken: 'receipt',
  );
  http.Response granted() => http.Response(
    jsonEncode({
      'ok': true,
      'isPremium': true,
      'premiumExpiresAt': expiry.toIso8601String(),
    }),
    200,
  );
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'auth_user_profile': UserProfile(
        id: 'google_123',
        name: 'Test',
        email: 'test@example.com',
        provider: AuthProviderType.google,
        createdAt: DateTime(2026),
      ).toJson(),
    });
    FlutterSecureStorage.setMockInitialValues({
      'pdd_server_session': jsonEncode({
        'userId': 'google_123',
        'token': 'test-session',
        'expiresAt': expiry.toIso8601String(),
      }),
    });
    await http.runWithClient(
      () async {
        await premium.init();
        await auth.init();
      },
      () => MockClient(
        (_) async => http.Response('{"ok":true,"isPremium":false}', 200),
      ),
    );
    expect(auth.hasServerSession, isTrue);
  });

  test('rejected verification never activates premium', () async {
    final result = await http.runWithClient(
      verify,
      () => MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer test-session');
        final body = jsonDecode(request.body) as Map;
        expect(body['purchaseToken'], 'receipt');
        expect(body.containsKey('expiresAt'), isFalse);
        return http.Response('{}', 503);
      }),
    );
    expect(result, isFalse);
    expect(premium.isPremium, isFalse);
  });
  test(
    'an expired or incomplete server response never activates premium',
    () async {
      for (final data in [
        {'ok': true, 'isPremium': true},
        {
          'ok': true,
          'isPremium': true,
          'premiumExpiresAt': '2020-01-01T00:00:00Z',
        },
      ]) {
        expect(
          await http.runWithClient(
            verify,
            () => MockClient((_) async => http.Response(jsonEncode(data), 200)),
          ),
          isFalse,
        );
        expect(premium.isPremium, isFalse);
      }
    },
  );
  test('failed deletion keeps the account available for retry', () async {
    expect(
      await http.runWithClient(
        auth.deleteAccount,
        () => MockClient((_) async => http.Response('{}', 503)),
      ),
      isFalse,
    );
    expect(auth.isAuthenticated, isTrue);
    expect(auth.hasServerSession, isTrue);
  });
  test('restore replay preserves the verified expiry exactly', () async {
    for (var i = 0; i < 2; i++) {
      expect(
        await http.runWithClient(
          verify,
          () => MockClient((_) async => granted()),
        ),
        isTrue,
      );
      expect(premium.expiresAt, expiry);
      expect(premium.isPremium, isTrue);
    }
  });
  test('late verification cannot re-enable premium after sign out', () async {
    final arrived = Completer<void>(), reply = Completer<http.Response>();
    await http.runWithClient(
      () async {
        final pending = verify();
        await arrived.future;
        await auth.signOut();
        reply.complete(granted());
        expect(await pending, isFalse);
        expect(premium.isPremium, isFalse);
        expect(auth.isAuthenticated, isFalse);
      },
      () => MockClient((request) async {
        if (request.url.path == '/api/user/purchase') {
          arrived.complete();
          return reply.future;
        }
        return http.Response('{}', 200);
      }),
    );
  });
}
