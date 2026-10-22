import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
// ignore: depend_on_referenced_packages
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:pdd_app/data/services/iap_service.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DiagnosticStore extends InAppPurchasePlatform {
  int queries = 0;
  Completer<ProductDetailsResponse>? pending;
  bool hang = false;
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => const Stream.empty();
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    queries++;
    if (hang) return Completer<ProductDetailsResponse>().future;
    if (pending != null) return pending!.future;
    return ProductDetailsResponse(
      productDetails: const [],
      notFoundIDs: ['ru.pdd.pddapp.sub.week', 'secret@example.com'],
      error: IAPError(
        source: 'app_store',
        code: 'channel-error',
        message: 'TOP_SECRET',
        details: 'TOP_SECRET',
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DiagnosticStore store;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    InAppPurchase.instance;
    store = DiagnosticStore();
    InAppPurchasePlatform.instance = store;
    IapService.productRetryUnit = Duration.zero;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    IapService.productQueryTimeout = const Duration(seconds: 10);
  });
  test('startup keeps the payment stream without fetching prices', () async {
    final iap = IapService.forTesting();
    addTearDown(iap.dispose);
    await iap.init();
    expect(store.queries, 0);
    expect(iap.isAvailable, isTrue);
  });
  test(
    'foreground failure reports final attempt, counts and only known missing IDs',
    () async {
      final events = <Map<String, dynamic>>[];
      final iap = IapService.forTesting(
        onProductDiagnostic: (code, context) =>
            events.add({'code': code, ...context}),
      );
      addTearDown(iap.dispose);
      await iap.loadProducts(phase: ProductLoadPhase.paywall);
      expect(store.queries, 3);
      expect(events, hasLength(1));
      expect(events.single['phase'], 'paywall');
      expect(events.single['stage'], 'query');
      expect(events.single['attempt'], 3);
      expect(events.single['returnedCount'], 0);
      expect(events.single['missingCount'], 2);
      expect(events.single['requestedCount'], 2);
      expect(events.single['missingIds'], [
        'ru.pdd.pddapp.sub.week',
        'ru.pdd.pddapp.sub.3months',
      ]);
      expect(events.single.toString(), isNot(contains('TOP_SECRET')));
      expect(events.single.toString(), isNot(contains('secret@example.com')));
    },
  );
  test(
    'purchase promotes an in-flight prefetch, shares its query and reports foreground failure',
    () async {
      store.pending = Completer<ProductDetailsResponse>();
      final events = <Map<String, dynamic>>[];
      final iap = IapService.forTesting(
        onProductDiagnostic: (code, context) => events.add(context),
      );
      addTearDown(iap.dispose);
      final background = iap.loadProducts();
      final foreground = iap.loadProducts(phase: ProductLoadPhase.purchase);
      await Future<void>.delayed(Duration.zero);
      expect(store.queries, 1);
      store.pending!.complete(
        ProductDetailsResponse(productDetails: const [], notFoundIDs: const []),
      );
      await Future.wait([background, foreground]);
      expect(store.queries, 3);
      expect(events.single['phase'], 'purchase');
    },
  );
  test(
    'purchase joining an in-flight paywall query can buy its returned tier without waiting for the other',
    () async {
      store.pending = Completer<ProductDetailsResponse>();
      final codes = <String>[];
      final iap = IapService.forTesting(
        onProductDiagnostic: (code, _) => codes.add(code),
      );
      addTearDown(iap.dispose);
      final paywall = iap.loadProducts(phase: ProductLoadPhase.paywall);
      await Future<void>.delayed(Duration.zero);
      final purchase = iap.loadProducts(
        phase: ProductLoadPhase.purchase,
        purchaseTier: PremiumTier.weekly,
      );
      store.pending!.complete(
        ProductDetailsResponse(
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
        ),
      );
      await Future.wait([paywall, purchase]);
      expect(store.queries, 1);
      expect(codes, isEmpty);
      expect(iap.storePrice(PremiumTier.weekly), '99 RUB');
      expect(iap.hasCompleteStoreProducts, isFalse);
    },
  );
  test(
    'a hung product query finishes with a bounded timeout diagnostic',
    () async {
      store.hang = true;
      IapService.productQueryTimeout = const Duration(milliseconds: 1);
      final codes = <String>[];
      final iap = IapService.forTesting(
        onProductDiagnostic: (code, _) => codes.add(code),
      );
      addTearDown(iap.dispose);
      await iap.loadProducts(phase: ProductLoadPhase.paywall);
      expect(store.queries, 3);
      expect(codes, ['timeout']);
    },
  );
}
