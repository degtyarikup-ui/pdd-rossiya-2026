import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/iap_service.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlayStore extends InAppPurchasePlatform {
  final updates = StreamController<List<PurchaseDetails>>.broadcast();
  int launches = 0;
  final completed = <String>[];
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async =>
      ProductDetailsResponse(
        productDetails: ids
            .map(
              (id) => ProductDetails(
                id: id,
                title: id,
                description: id,
                price: '1 USD',
                rawPrice: 1,
                currencyCode: 'USD',
              ),
            )
            .toList(),
        notFoundIDs: [],
      );
  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    launches++;
    updates.add([
      PurchaseDetails(
        productID: purchaseParam.productDetails.id,
        verificationData: PurchaseVerificationData(
          localVerificationData: '',
          serverVerificationData: '',
          source: 'google_play',
        ),
        transactionDate: null,
        status: PurchaseStatus.pending,
      ),
    ]);
    // Play cancellation has no product ID. It must clear the active reservation.
    updates.add([
      PurchaseDetails(
        productID: '',
        verificationData: PurchaseVerificationData(
          localVerificationData: '',
          serverVerificationData: '',
          source: 'google_play',
        ),
        transactionDate: null,
        status: PurchaseStatus.canceled,
      ),
    ]);
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed.add(purchase.productID);
  }
}

GooglePlayPurchaseDetails payment(
  String product,
  String owner,
  PurchaseStateWrapper state,
) => GooglePlayPurchaseDetails.fromPurchase(
  PurchaseWrapper(
    orderId: 'order',
    packageName: 'ru.pdd.pdd_app',
    purchaseTime: 1,
    purchaseToken: 'receipt',
    signature: '',
    products: [product],
    isAutoRenewing: true,
    originalJson: '{}',
    isAcknowledged: false,
    purchaseState: state,
    obfuscatedAccountId: sha256.convert(utf8.encode(owner)).toString(),
  ),
).single;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Play repairs old reservations, preserves real owners, and never charges after restore',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      InAppPurchase.instance;
      final store = PlayStore();
      InAppPurchasePlatform.instance = store;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() async {
        debugDefaultTargetPlatformOverride = null;
        await store.updates.close();
      });
      final expiry = DateTime.now().toUtc().add(const Duration(days: 7));
      final user = UserProfile(
        id: 'google_B',
        name: 'B',
        email: '',
        provider: AuthProviderType.google,
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
          for (final tier in [PremiumTier.weekly, PremiumTier.threeMonths]) {
            final product = tier == PremiumTier.weekly
                ? IapService.productIdWeek
                : IapService.productId3Months;
            for (final scenario in [
              'stale',
              'query_error',
              'foreign_pending',
              'own_pending',
              'foreign_paid',
              'own_paid',
            ]) {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(
                'iap_pending_owners_v1',
                jsonEncode({product: 'google_A'}),
              );
              final response = QueryPurchaseDetailsResponse(
                pastPurchases: switch (scenario) {
                  'foreign_pending' => [
                    payment(product, 'google_A', PurchaseStateWrapper.pending),
                  ],
                  'own_pending' => [
                    payment(product, 'google_B', PurchaseStateWrapper.pending),
                  ],
                  'foreign_paid' => [
                    payment(
                      product,
                      'google_A',
                      PurchaseStateWrapper.purchased,
                    ),
                  ],
                  'own_paid' => [
                    payment(
                      product,
                      'google_B',
                      PurchaseStateWrapper.purchased,
                    ),
                  ],
                  _ => [],
                },
                error: scenario == 'query_error'
                    ? IAPError(
                        source: 'google_play',
                        code: 'error',
                        message: '',
                      )
                    : null,
              );
              final iap = IapService.forTesting(
                queryPlayPurchases: () async => response,
              );
              await iap.init();
              final launches = store.launches;
              final verified = verifications;
              final result = await iap.buyProduct(tier);
              if (scenario == 'stale') {
                expect(result, PurchaseResult.canceled);
                expect(store.launches, launches + 1);
                expect(await iap.buyProduct(tier), PurchaseResult.canceled);
                expect(store.launches, launches + 2);
                expect(
                  jsonDecode(prefs.getString('iap_pending_owners_v1')!),
                  isEmpty,
                );
              } else {
                expect(store.launches, launches, reason: scenario);
                expect(
                  result,
                  scenario == 'own_paid'
                      ? PurchaseResult.success
                      : scenario == 'query_error'
                      ? PurchaseResult.storeUnavailable
                      : PurchaseResult.error,
                );
                if (scenario.startsWith('foreign')) {
                  expect(iap.lastFailure, PurchaseFailure.accountMismatch);
                  expect(verifications, verified);
                }
                if (scenario == 'own_pending') {
                  expect(iap.lastFailure, PurchaseFailure.paymentPending);
                  expect(await iap.buyProduct(tier), PurchaseResult.error);
                  expect(iap.lastFailure, PurchaseFailure.paymentPending);
                  expect(store.launches, launches);
                }
                if (scenario == 'query_error') {
                  expect(
                    prefs.getString('iap_pending_owners_v1'),
                    contains('google_A'),
                  );
                }
                if (scenario == 'own_paid') expect(verifications, verified + 1);
              }
              iap.dispose();
            }
          }
        },
        () => MockClient((request) async {
          if (request.url.path == '/api/user/store/status') {
            return http.Response('{"configured":true}', 200);
          }
          if (request.url.path == '/api/user/purchase') {
            verifications++;
            expect(jsonDecode(request.body)['userId'], 'google_B');
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
    },
  );

  test(
    'payment diagnostics keep the Play response without arbitrary SDK text',
    () {
      expect(
        IapService.paymentErrorCode(
          IAPError(
            source: 'google_play',
            code: 'purchase_error',
            message: 'BillingResponse.itemAlreadyOwned',
          ),
        ),
        'play_itemAlreadyOwned',
      );
      expect(
        IapService.paymentErrorCode(
          IAPError(
            source: 'google_play',
            code: 'purchase_error',
            message: 'private@example.com',
          ),
        ),
        'purchase_error',
      );
    },
  );
}
