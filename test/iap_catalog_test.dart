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
import 'package:pdd_app/data/services/device_region.dart';
import 'package:pdd_app/data/services/iap_service.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProductDetails product(String id, [String price = '99 RUB']) => ProductDetails(
  id: id,
  title: id,
  description: id,
  price: price,
  rawPrice: 99,
  currencyCode: 'RUB',
);

class CatalogStore extends InAppPurchasePlatform {
  final requests = <Set<String>>[];
  List<ProductDetails> products = [];
  IAPError? error;
  PurchaseParam? launched;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => const Stream.empty();
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    requests.add(Set.of(ids));
    return ProductDetailsResponse(
      productDetails: products,
      notFoundIDs:
          const [], // Some platform responses omit individual failures.
      error: error,
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    launched = purchaseParam;
    return false; // Exercise launch parameters without creating a transaction.
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CatalogStore store;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    InAppPurchase.instance;
    store = CatalogStore();
    InAppPurchasePlatform.instance = store;
    IapService.productRetryUnit = Duration.zero;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    IapService.productRetryUnit = const Duration(seconds: 2);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('$platform queries only its two verified storefront IDs', () async {
      debugDefaultTargetPlatformOverride = platform;
      final ids = platform == TargetPlatform.iOS
          ? {'u.pdd.pddApp.premium.week', 'ru.pdd.pddApp.sub.3months'}
          : {'ru.pdd.pddapp.sub.week', 'ru.pdd.pddapp.sub.3months'};
      store.products = ids.map(product).toList();
      final iap = IapService.forTesting();
      addTearDown(iap.dispose);
      await iap.loadProducts(phase: ProductLoadPhase.paywall);
      expect(store.requests, [ids]);
      expect(iap.hasCompleteStoreProducts, isTrue);
    });
  }

  test(
    'a partial catalogue preserves the available tier and retries the missing one',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      store.products = [product('ru.pdd.pddapp.sub.week')];
      final diagnostics = <Map<String, dynamic>>[];
      final iap = IapService.forTesting(
        onProductDiagnostic: (code, context) =>
            diagnostics.add({'code': code, ...context}),
      );
      addTearDown(iap.dispose);
      await iap.loadProducts(phase: ProductLoadPhase.paywall);
      expect(iap.hasStoreProducts, isTrue);
      expect(iap.hasCompleteStoreProducts, isFalse);
      expect(iap.storePrice(PremiumTier.weekly), '99 RUB');
      expect(iap.storePrice(PremiumTier.threeMonths), isNull);
      expect(store.requests, hasLength(3));
      expect(diagnostics.single['code'], 'products_incomplete');
      expect(diagnostics.single['missingCount'], 1);
      expect(diagnostics.single['missingIds'], ['ru.pdd.pddapp.sub.3months']);
      // Buying the available tier does not wait for the missing other tariff.
      await iap.loadProducts(
        phase: ProductLoadPhase.purchase,
        purchaseTier: PremiumTier.weekly,
      );
      expect(store.requests, hasLength(4));
      store.products = [
        ...store.products,
        product('ru.pdd.pddapp.sub.3months', '290 RUB'),
      ];
      await iap.loadProducts(phase: ProductLoadPhase.paywall);
      expect(iap.hasCompleteStoreProducts, isTrue);
      expect(iap.storePrice(PremiumTier.threeMonths), '290 RUB');
    },
  );

  test('a guessed alias is never used as a purchasable tariff', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    store.products = [product('weekly')];
    final iap = IapService.forTesting();
    addTearDown(iap.dispose);
    await iap.loadProducts(
      phase: ProductLoadPhase.purchase,
      purchaseTier: PremiumTier.weekly,
    );
    expect(iap.hasStoreProducts, isFalse);
    expect(iap.storePrice(PremiumTier.weekly), isNull);
  });

  test(
    'SDK query failure removes purchasable details but keeps the last display price',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      store.products = [
        product('ru.pdd.pddapp.sub.week'),
        product('ru.pdd.pddapp.sub.3months'),
      ];
      final iap = IapService.forTesting();
      addTearDown(iap.dispose);
      await iap.loadProducts(phase: ProductLoadPhase.paywall);
      store.error = IAPError(
        source: 'google_play',
        code: 'service_disconnected',
        message: 'test',
      );
      await iap.loadProducts(phase: ProductLoadPhase.paywall);
      expect(iap.hasStoreProducts, isFalse);
      expect(iap.storePrice(PremiumTier.weekly), '99 RUB');
    },
  );

  test(
    'purchase refreshes its offer and never launches with stale or missing ProductDetails',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final profile = UserProfile(
        id: 'google_catalog',
        name: 'Test',
        email: '',
        provider: AuthProviderType.google,
        createdAt: DateTime(2026),
      );
      SharedPreferences.setMockInitialValues({
        'auth_user_profile': profile.toJson(),
      });
      FlutterSecureStorage.setMockInitialValues({
        'pdd_server_session': jsonEncode({
          'userId': profile.id,
          'token': 'fixture',
          'expiresAt': DateTime.now()
              .add(const Duration(days: 1))
              .toIso8601String(),
        }),
      });
      DeviceRegion.readPlayCountry = () async => 'DE';
      addTearDown(() => DeviceRegion.resetPlayCountry());
      await http.runWithClient(
        () async {
          await AuthService.instance.init();
          final old = product('ru.pdd.pddapp.sub.week', '99 RUB');
          final current = product('ru.pdd.pddapp.sub.week', '119 RUB');
          store.products = [old, product('ru.pdd.pddapp.sub.3months')];
          final iap = IapService.forTesting();
          addTearDown(iap.dispose);
          await iap.loadProducts(phase: ProductLoadPhase.paywall);
          store.products = [current];
          expect(
            await iap.buyProduct(PremiumTier.weekly),
            PurchaseResult.error,
          );
          expect(identical(store.launched?.productDetails, current), isTrue);
          expect(store.requests, hasLength(2));
          store.launched = null;
          store.products = [];
          expect(
            await iap.buyProduct(PremiumTier.weekly),
            PurchaseResult.productNotFound,
          );
          expect(store.launched, isNull);
        },
        () => MockClient(
          (request) async =>
              http.Response(jsonEncode({'configured': true}), 200),
        ),
      );
    },
  );
}
