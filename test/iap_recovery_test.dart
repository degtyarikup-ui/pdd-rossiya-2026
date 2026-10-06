import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
// The fake replaces the store boundary while exercising the real service.
// ignore: depend_on_referenced_packages
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/iap_service.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeStore extends InAppPurchasePlatform {
  final updates = StreamController<List<PurchaseDetails>>.broadcast();
  final completed = <String?>[];
  final product = ProductDetails(
    id: 'u.pdd.pddApp.premium.week',
    title: 'Week',
    description: 'Week',
    price: r'$0.99',
    rawPrice: .99,
    currencyCode: 'USD',
  );
  PurchaseStatus nextStatus = PurchaseStatus.purchased;
  int sequence = 0;
  bool failAcknowledgement = false;
  PurchaseDetails payment(PurchaseStatus status) => PurchaseDetails(
    purchaseID: '${++sequence}',
    productID: product.id,
    verificationData: PurchaseVerificationData(
      localVerificationData: '',
      serverVerificationData: 'receipt',
      source: 'app_store',
    ),
    transactionDate: '0',
    status: status,
  )..pendingCompletePurchase = true;
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async => ProductDetailsResponse(productDetails: [product], notFoundIDs: []);
  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    updates.add([payment(nextStatus)]);
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    if (failAcknowledgement) {
      failAcknowledgement = false;
      throw StateError('temporary store failure');
    }
    completed.add(purchase.purchaseID);
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    updates.add([]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'payment retries after network failure and finishes only after delivery; restored purchase finishes buy flow',
    () async {
      final store = FakeStore();
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      InAppPurchase
          .instance; // Construct wrapper without auto-registering a native store.
      InAppPurchasePlatform.instance = store;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final iap = IapService.instance;
      addTearDown(() async {
        iap.dispose();
        await store.updates.close();
        debugDefaultTargetPlatformOverride = null;
      });
      final expiry = DateTime.now().toUtc().add(const Duration(days: 7));
      SharedPreferences.setMockInitialValues({
        'auth_user_profile': UserProfile(
          id: 'apple_test',
          name: 'Test',
          email: 'test@example.com',
          provider: AuthProviderType.apple,
          createdAt: DateTime(2026),
        ).toJson(),
      });
      FlutterSecureStorage.setMockInitialValues({
        'pdd_server_session': jsonEncode({
          'userId': 'apple_test',
          'token': 'session',
          'expiresAt': expiry.toIso8601String(),
        }),
      });
      bool online = false;
      int verifications = 0;
      final delivered = Completer<void>();
      await http.runWithClient(
        () async {
          await PremiumService.instance.init();
          await AuthService.instance.init();
          await Future.wait([iap.init(), iap.init()]);
          expect(
            await iap.buyProduct(PremiumTier.weekly),
            PurchaseResult.error,
          );
          expect(verifications, 1);
          expect(store.completed, isEmpty);
          expect(PremiumService.instance.isPremium, isFalse);
          online = true;
          iap.retryPendingPurchases();
          await delivered.future;
          // Verification and acknowledgement are asynchronous stream processing.
          for (var i = 0; i < 20 && store.completed.isEmpty; i++) {
            await Future<void>.delayed(Duration.zero);
          }
          expect(store.completed, ['1']);
          expect(PremiumService.instance.isPremium, isTrue);
          expect(PremiumService.instance.expiresAt, expiry);
          store.nextStatus = PurchaseStatus.restored;
          store.failAcknowledgement = true;
          expect(
            await iap.buyProduct(PremiumTier.weekly),
            PurchaseResult.success,
          );
          iap.retryPendingPurchases();
          for (var i = 0; i < 20 && !store.completed.contains('2'); i++) {
            await Future<void>.delayed(Duration.zero);
          }
          expect(store.completed, ['1', '2']);
          expect(await iap.restorePurchases(), isFalse);
          await AuthService.instance.signOut();
          store.updates.add([store.payment(PurchaseStatus.purchased)]);
          for (var i = 0; i < 20; i++) {
            await Future<void>.delayed(Duration.zero);
          }
          expect(store.completed.contains('3'), isFalse);
          expect(PremiumService.instance.isPremium, isFalse);
        },
        () => MockClient((request) async {
          if (request.url.path == '/api/user/store/status') {
            return http.Response('{"configured":true}', 200);
          }
          if (request.url.path == '/api/user/purchase') {
            verifications++;
            expect(jsonDecode(request.body)['store'], 'appstore');
            if (!online) return http.Response('{}', 503);
            if (!delivered.isCompleted) delivered.complete();
            return http.Response(
              jsonEncode({
                'ok': true,
                'isPremium': true,
                'premiumExpiresAt': expiry.toIso8601String(),
              }),
              200,
            );
          }
          return http.Response('{"ok":true,"isPremium":false}', 200);
        }),
      );
    },
  );
}
