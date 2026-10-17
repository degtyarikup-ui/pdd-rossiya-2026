import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
// ignore: depend_on_referenced_packages
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/iap_service.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'iap_recovery_test.dart' show FakeStore;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'iOS token and durable owner survive service restart and another login',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      InAppPurchase.instance;
      final store = FakeStore()..nextStatus = PurchaseStatus.pending;
      InAppPurchasePlatform.instance = store;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      var iap = IapService.forTesting();
      final expiry = DateTime.now().add(const Duration(days: 7));
      UserProfile user(String name) => UserProfile(
        id: 'apple_$name',
        name: name,
        email: '',
        provider: AuthProviderType.apple,
        createdAt: DateTime(2026),
      );
      SharedPreferences.setMockInitialValues({
        'auth_user_profile': user('A').toJson(),
      });
      FlutterSecureStorage.setMockInitialValues({
        'pdd_server_session': jsonEncode({
          'userId': 'apple_A',
          'token': 'session-A',
          'expiresAt': expiry.toIso8601String(),
        }),
      });
      final owners = <String>[];
      Future<void> drain() async {
        for (var i = 0; i < 40; i++) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      await http.runWithClient(
        () async {
          final auth = AuthService.instance;
          await PremiumService.instance.init();
          await auth.init();
          await iap.init();
          iap.buyProduct(PremiumTier.weekly).ignore();
          await drain();
          expect(
            store.lastPurchaseParam?.applicationUserName,
            '11111111-1111-5111-8111-111111111111',
          );
          expect(
            (await SharedPreferences.getInstance()).getString(
              'iap_pending_owners_v1',
            ),
            contains('apple_A'),
          );
          iap.dispose();
          await auth.completeSignInForTesting(user('B'), 'credential');
          iap = IapService.forTesting();
          await iap.init();
          store.updates.add([store.payment(PurchaseStatus.purchased)]);
          await drain();
          expect(owners, isEmpty);
          expect(store.completed, isEmpty);
          expect(
            (await SharedPreferences.getInstance()).getString(
              'iap_pending_owners_v1',
            ),
            contains('apple_A'),
          );
          await auth.completeSignInForTesting(user('A'), 'credential');
          await drain();
          expect(owners, ['apple_A']);
          expect(store.completed, hasLength(1));
          expect(
            jsonDecode(
              (await SharedPreferences.getInstance()).getString(
                'iap_pending_owners_v1',
              )!,
            ),
            isEmpty,
          );
          store.launchSucceeds = false;
          expect(
            await iap.buyProduct(PremiumTier.weekly),
            PurchaseResult.error,
          );
          expect(
            jsonDecode(
              (await SharedPreferences.getInstance()).getString(
                'iap_pending_owners_v1',
              )!,
            ),
            isEmpty,
            reason: 'A refused OS launch cannot reserve the product forever',
          );
          iap.dispose();
        },
        () => MockClient((request) async {
          if (request.url.path == '/api/user/store/account-token') {
            return http.Response(
              '{"accountToken":"11111111-1111-5111-8111-111111111111"}',
              200,
            );
          }
          if (request.url.path == '/api/user/store/status') {
            return http.Response('{"configured":true}', 200);
          }
          if (request.url.path == '/api/auth/session') {
            final profile = user(jsonDecode(request.body)['name']);
            return http.Response(
              jsonEncode({
                'user': profile.toMap(),
                'token': 'session-${profile.name}',
                'expiresAt': expiry.toIso8601String(),
              }),
              200,
            );
          }
          if (request.url.path == '/api/user/purchase') {
            owners.add(jsonDecode(request.body)['userId']);
            return http.Response(
              jsonEncode({
                'ok': true,
                'isPremium': true,
                'premiumExpiresAt': expiry.toIso8601String(),
              }),
              200,
            );
          }
          return http.Response('{"isPremium":false}', 200);
        }),
      );
      await store.updates.close();
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
