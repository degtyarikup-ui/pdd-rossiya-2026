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
    productId: 'ru.pdd.pddapp.sub.week',
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
        if (request.url.path != '/api/user/purchase') {
          return http.Response('{}', 503);
        }
        expect(request.headers['authorization'], 'Bearer test-session');
        final body = jsonDecode(request.body) as Map;
        expect(body['purchaseToken'], 'receipt');
        expect(body.containsKey('expiresAt'), isFalse);
        return http.Response('{}', 503);
      }),
    );
    expect(result, isFalse);
    expect(
      premium.purchaseVerificationFailure,
      PurchaseVerificationFailure.unavailable,
    );
    expect(premium.isPremium, isFalse);
  });
  test('terminal store rejection does not schedule a network retry', () async {
    expect(
      await http.runWithClient(
        verify,
        () => MockClient((_) async => http.Response('{}', 403)),
      ),
      isFalse,
    );
    expect(
      premium.purchaseVerificationFailure,
      PurchaseVerificationFailure.rejected,
    );
    expect(premium.isPremium, isFalse);
  });
  test(
    'legacy Apple ownership rejection requires support and cannot become retryable',
    () async {
      expect(
        await http.runWithClient(
          verify,
          () => MockClient(
            (_) async => http.Response(
              '{"error":"legacy purchase owner required"}',
              409,
            ),
          ),
        ),
        isFalse,
      );
      expect(
        premium.purchaseVerificationFailure,
        PurchaseVerificationFailure.legacyOwnerRequired,
      );
      expect(premium.isPremium, isFalse);
    },
  );
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
  test(
    'a lost verification answer re-reads the account and shows its Premium',
    () async {
      final synced = Completer<void>();
      await http.runWithClient(
        () async {
          expect(await verify(), isFalse);
          expect(
            premium.purchaseVerificationFailure,
            PurchaseVerificationFailure.unavailable,
          );
          await synced.future;
          for (var i = 0; i < 20 && !premium.isPremium; i++) {
            await Future<void>.delayed(Duration.zero);
          }
          expect(premium.isPremium, isTrue);
          expect(premium.expiresAt, expiry);
        },
        () => MockClient((request) async {
          if (request.url.path == '/api/user/purchase') {
            // The server committed the purchase; the phone lost the answer.
            throw http.ClientException('connection closed');
          }
          if (request.url.path == '/api/user/sync') {
            if (!synced.isCompleted) synced.complete();
            return granted();
          }
          return http.Response('{}', 404);
        }),
      );
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
  test('late pre-purchase sync cannot revoke delivered access', () async {
    final arrived = Completer<void>(), reply = Completer<http.Response>();
    await http.runWithClient(
      () async {
        final syncing = premium.syncWithServer();
        await arrived.future;
        expect(await verify(), isTrue);
        reply.complete(http.Response('{"isPremium":false}', 200));
        await syncing;
        expect(premium.isPremium, isTrue);
        expect(premium.expiresAt, expiry);
      },
      () => MockClient((request) async {
        if (request.url.path == '/api/user/sync') {
          arrived.complete();
          return reply.future;
        }
        return granted();
      }),
    );
  });
  for (final status in [503, 504]) {
    test(
      'HTTP $status after a committed receipt reconciles account access',
      () async {
        var checks = 0;
        var syncs = 0;
        final refreshedExpiry = expiry.add(Duration(days: status));
        final synced = Completer<void>();
        await http.runWithClient(
          () async {
            expect(await verify(), isFalse);
            expect(
              premium.purchaseVerificationFailure,
              PurchaseVerificationFailure.unavailable,
            );
            await synced.future;
            for (
              var i = 0;
              i < 20 && premium.expiresAt != refreshedExpiry;
              i++
            ) {
              await Future<void>.delayed(Duration.zero);
            }
            expect(checks, 1);
            expect(syncs, 1);
            expect(premium.isPremium, isTrue);
            expect(premium.expiresAt, refreshedExpiry);
          },
          () => MockClient((request) async {
            if (request.url.path == '/api/user/purchase') {
              checks++;
              return http.Response('upstream unavailable', status);
            }
            if (request.url.path == '/api/user/sync') {
              syncs++;
              synced.complete();
              return http.Response(
                jsonEncode({
                  'isPremium': true,
                  'premiumExpiresAt': refreshedExpiry.toIso8601String(),
                }),
                200,
              );
            }
            return http.Response('{}', 404);
          }),
        );
      },
    );
  }
  test(
    'malformed status responses cannot revoke or make access permanent',
    () async {
      final validExpiry = premium.expiresAt;
      for (final data in [
        <String, dynamic>{},
        {'isPremium': true},
        {'isPremium': 'false'},
        {'isPremium': false, 'premiumExpiresAt': 'broken'},
        {'isPremium': true, 'premiumExpiresAt': 'broken'},
      ]) {
        await http.runWithClient(() async {
          await premium.syncWithServer();
          await premium.checkForGrant();
        }, () => MockClient((_) async => http.Response(jsonEncode(data), 200)));
        expect(premium.isPremium, isTrue);
        expect(premium.expiresAt, validExpiry);
      }
      // A valid authoritative revocation must still be respected.
      await http.runWithClient(
        premium.checkForGrant,
        () =>
            MockClient((_) async => http.Response('{"isPremium":false}', 200)),
      );
      expect(premium.isPremium, isFalse);
    },
  );
  test(
    'status refresh updates renewed expiry while premium remains active',
    () async {
      final renewedExpiry = expiry.add(const Duration(days: 7));
      await http.runWithClient(
        premium.checkForGrant,
        () => MockClient(
          (_) async => http.Response(
            jsonEncode({
              'isPremium': true,
              'premiumExpiresAt': renewedExpiry.toIso8601String(),
            }),
            200,
          ),
        ),
      );
      expect(premium.isPremium, isTrue);
      expect(premium.expiresAt, renewedExpiry);
    },
  );
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
