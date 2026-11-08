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

class LegacyRestoreStore extends FakeStore {
  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    updates.add([payment(PurchaseStatus.restored)]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'unbound legacy Apple restore terminates promptly, never acknowledges or auto retries',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      InAppPurchase.instance;
      final store = LegacyRestoreStore();
      InAppPurchasePlatform.instance = store;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final iap = IapService.forTesting();
      addTearDown(() async {
        iap.dispose();
        await store.updates.close();
        debugDefaultTargetPlatformOverride = null;
      });
      final expiry = DateTime.now().add(const Duration(days: 7));
      final user = UserProfile(
        id: 'apple_legacy',
        name: 'Test',
        email: '',
        provider: AuthProviderType.apple,
        createdAt: DateTime(2026),
      );
      SharedPreferences.setMockInitialValues({
        'auth_user_profile': user.toJson(),
      });
      FlutterSecureStorage.setMockInitialValues({
        'pdd_server_session': jsonEncode({
          'userId': user.id,
          'token': 'session',
          'expiresAt': expiry.toIso8601String(),
        }),
      });
      var verifications = 0;
      await http.runWithClient(
        () async {
          await PremiumService.instance.init();
          await AuthService.instance.init();
          await iap.init();
          expect(
            await iap.restorePurchases().timeout(const Duration(seconds: 2)),
            isFalse,
          );
          expect(iap.lastFailure, PurchaseFailure.legacyOwnerRequired);
          expect(store.completed, isEmpty);
          expect(PremiumService.instance.isPremium, isFalse);
          iap.retryPendingPurchases();
          for (var i = 0; i < 20; i++) {
            await Future<void>.delayed(Duration.zero);
          }
          expect(verifications, 1);
        },
        () => MockClient((request) async {
          if (request.url.path == '/api/user/purchase') {
            verifications++;
            return http.Response(
              '{"error":"legacy purchase owner required"}',
              409,
            );
          }
          return http.Response('{"ok":true,"isPremium":false}', 200);
        }),
      );
    },
  );
}
