import 'dart:async';
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

class _DeferredStore extends InAppPurchasePlatform {
  final updates = StreamController<List<PurchaseDetails>>.broadcast();
  final completed = <String?>[];
  final buyLaunched = Completer<void>();
  final restoreLaunched = Completer<void>();
  final product = ProductDetails(
    id: 'u.pdd.pddApp.premium.week',
    title: 'Week',
    description: 'Week',
    price: r'$0.99',
    rawPrice: .99,
    currencyCode: 'USD',
  );

  PurchaseDetails payment(String id, PurchaseStatus status) => PurchaseDetails(
    purchaseID: id,
    productID: product.id,
    verificationData: PurchaseVerificationData(
      localVerificationData: '',
      serverVerificationData: 'test-receipt',
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
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async =>
      ProductDetailsResponse(productDetails: [product], notFoundIDs: []);
  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    buyLaunched.complete();
    return true;
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restoreLaunched.complete();
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed.add(purchase.purchaseID);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('delayed iOS purchases and restores keep the initiating account', () async {
    final store = _DeferredStore();
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    InAppPurchase.instance;
    InAppPurchasePlatform.instance = store;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final iap = IapService.instance;
    addTearDown(() async {
      iap.dispose();
      await store.updates.close();
      debugDefaultTargetPlatformOverride = null;
    });
    final expiry = DateTime.now().toUtc().add(const Duration(days: 7));
    UserProfile profile(String name) => UserProfile(
      id: 'apple_$name',
      name: name,
      email: '',
      provider: AuthProviderType.apple,
      createdAt: DateTime(2026),
    );
    SharedPreferences.setMockInitialValues({
      'auth_user_profile': profile('first').toJson(),
    });
    FlutterSecureStorage.setMockInitialValues({
      'pdd_server_session': jsonEncode({
        'userId': 'apple_first',
        'token': 'session-first',
        'expiresAt': expiry.toIso8601String(),
      }),
    });
    final verifiedOwners = <String>[];
    Future<void> drain() async {
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    final auth = AuthService.instance;
    await http.runWithClient(
      () async {
        await PremiumService.instance.init();
        await auth.init();
        await iap.init();
        final buying = iap.buyProduct(PremiumTier.weekly);
        await store.buyLaunched.future;
        // Ask to Buy / StoreKit can stay pending while authentication changes.
        store.updates.add([store.payment('purchase', PurchaseStatus.pending)]);
        await drain();
        store.updates.addError(StateError('temporary StoreKit stream failure'));
        expect(await buying, PurchaseResult.error);
        expect(
          await auth.completeSignInForTesting(profile('second'), 'token'),
          isTrue,
        );
        store.updates.add([
          store.payment('purchase', PurchaseStatus.purchased),
        ]);
        await drain();
        expect(verifiedOwners, isEmpty);
        expect(store.completed, isEmpty);

        // The unfinished transaction is delivered once its owner signs back in.
        expect(
          await auth.completeSignInForTesting(profile('first'), 'token'),
          isTrue,
        );
        await drain();
        expect(verifiedOwners, ['apple_first']);
        expect(store.completed, ['purchase']);

        final restoring = iap.restorePurchases();
        await store.restoreLaunched.future;
        expect(
          await auth.completeSignInForTesting(profile('second'), 'token'),
          isTrue,
        );
        store.updates.add([store.payment('restore', PurchaseStatus.restored)]);
        expect(await restoring, isFalse);
        expect(verifiedOwners, ['apple_first']);
        expect(store.completed, ['purchase']);
        expect(
          await auth.completeSignInForTesting(profile('first'), 'token'),
          isTrue,
        );
        await drain();
        expect(verifiedOwners, ['apple_first', 'apple_first']);
        expect(store.completed, ['purchase', 'restore']);

        // An automatic replay with no locally initiated operation uses the
        // authenticated account, so restoration after restart still works.
        store.updates.add([store.payment('replay', PurchaseStatus.restored)]);
        await drain();
        expect(verifiedOwners, ['apple_first', 'apple_first', 'apple_first']);
        expect(store.completed, ['purchase', 'restore', 'replay']);
      },
      () => MockClient((request) async {
        if (request.url.path == '/api/auth/session') {
          final body = jsonDecode(request.body) as Map;
          final user = profile(body['name'] as String);
          return http.Response(
            jsonEncode({
              'user': user.toMap(),
              'token': 'session-${user.name}',
              'expiresAt': expiry.toIso8601String(),
            }),
            200,
          );
        }
        if (request.url.path == '/api/user/store/status') {
          return http.Response('{"configured":true}', 200);
        }
        if (request.url.path == '/api/user/purchase') {
          verifiedOwners.add(
            (jsonDecode(request.body) as Map)['userId'] as String,
          );
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
  });
}
