import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
// The fake verifies that the native billing boundary is never touched in RuStore.
// ignore: depend_on_referenced_packages
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:pdd_app/core/config/store_config.dart';
import 'package:pdd_app/data/services/iap_service.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CountingBillingStore extends InAppPurchasePlatform {
  final updates = StreamController<List<PurchaseDetails>>.broadcast();
  int streamReads = 0;
  int availabilityChecks = 0;
  int productQueries = 0;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream {
    streamReads++;
    return updates.stream;
  }

  @override
  Future<bool> isAvailable() async {
    availabilityChecks++;
    return true;
  }

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    productQueries++;
    return ProductDetailsResponse(
      productDetails: [
        ProductDetails(
          id: 'ru.pdd.pddapp.sub.week',
          title: 'Week',
          description: 'Week',
          price: '99 RUB',
          rawPrice: 99,
          currencyCode: 'RUB',
        ),
      ],
      notFoundIDs: const [],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Android billing boundary follows the compiled distribution', () async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    InAppPurchase.instance;
    final store = CountingBillingStore();
    InAppPurchasePlatform.instance = store;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final iap = IapService.instance;
    addTearDown(() async {
      iap.dispose();
      await store.updates.close();
      debugDefaultTargetPlatformOverride = null;
    });

    await iap.init();
    await iap.loadProducts();
    if (StoreConfig.current == AppStore.rustore) {
      expect(
        await iap.buyProduct(PremiumTier.weekly),
        PurchaseResult.storeUnavailable,
      );
      expect(await iap.restorePurchases(), isFalse);
      iap.retryPendingPurchases();
      expect(store.streamReads, 0);
      expect(store.availabilityChecks, 0);
      expect(store.productQueries, 0);
      expect(iap.isAvailable, isFalse);
      expect(iap.products, isEmpty);
    } else {
      expect(store.streamReads, 1);
      expect(store.availabilityChecks, 1);
      expect(store.productQueries, 2);
      expect(iap.isAvailable, isTrue);
      expect(iap.products, isNotEmpty);
    }
  });
}
