import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
// ignore: depend_on_referenced_packages
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:pdd_app/data/services/iap_service.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SlowStore extends InAppPurchasePlatform {
  int queries = 0;
  Duration latency = Duration.zero;
  Completer<ProductDetailsResponse>? pending;
  String price = '99 RUB';

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => const Stream.empty();
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    queries++;
    if (pending != null) return pending!.future;
    await Future<void>.delayed(latency);
    return response();
  }

  ProductDetailsResponse response() => ProductDetailsResponse(
    productDetails: [IapService.productIdWeek, IapService.productId3Months]
        .map(
          (id) => ProductDetails(
            id: id,
            title: id,
            description: id,
            price: price,
            rawPrice: 99,
            currencyCode: 'RUB',
          ),
        )
        .toList(),
    notFoundIDs: [],
  );
}

Future<void> _advance(WidgetTester tester, int seconds) async {
  await tester.pump();
  for (var second = 0; second < seconds; second++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

void _testStoreWidgets(
  String description,
  Future<void> Function(WidgetTester) body,
) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  late _SlowStore store;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    InAppPurchase.instance;
    store = _SlowStore();
    InAppPurchasePlatform.instance = store;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  _testStoreWidgets(
    'a 12 second native success survives the 10 second UI wait',
    (tester) async {
      store.latency = const Duration(seconds: 12);
      final diagnostics = <String>[];
      final iap = IapService.forTesting(
        onProductDiagnostic: (code, _) => diagnostics.add(code),
      );
      addTearDown(iap.dispose);
      var finished = false;
      unawaited(
        iap
            .loadProducts(phase: ProductLoadPhase.paywall)
            .then((_) => finished = true),
      );
      await _advance(tester, 14);
      expect(finished, true);
      expect(store.queries, 1);
      expect(iap.hasCompleteStoreProducts, true);
      expect(diagnostics, isEmpty);
    },
  );

  _testStoreWidgets(
    'hung queries are bounded to one per load cycle and a later cycle recovers',
    (tester) async {
      store.pending = Completer<ProductDetailsResponse>();
      final diagnostics = <String>[];
      final iap = IapService.forTesting(
        onProductDiagnostic: (code, _) => diagnostics.add(code),
      );
      addTearDown(iap.dispose);
      for (var attempt = 0; attempt < 2; attempt++) {
        var finished = false;
        unawaited(
          iap
              .loadProducts(phase: ProductLoadPhase.paywall)
              .then((_) => finished = true),
        );
        await _advance(tester, 37);
        expect(finished, true);
        expect(iap.hasStoreProducts, false);
        expect(store.queries, attempt + 1);
      }
      expect(diagnostics, ['timeout', 'timeout']);
      store.pending = null;
      unawaited(iap.loadProducts(phase: ProductLoadPhase.paywall));
      await _advance(tester, 1);
      expect(store.queries, 3);
      expect(iap.hasCompleteStoreProducts, true);
    },
  );

  _testStoreWidgets(
    'late success updates listeners and the next purchase refreshes its offer',
    (tester) async {
      store.pending = Completer<ProductDetailsResponse>();
      final iap = IapService.forTesting();
      addTearDown(iap.dispose);
      var notifications = 0;
      iap.addListener(() => notifications++);
      unawaited(iap.loadProducts(phase: ProductLoadPhase.paywall));
      await _advance(tester, 37);
      expect(iap.hasStoreProducts, false);
      store.pending!.complete(store.response());
      await tester.pump();
      expect(iap.hasCompleteStoreProducts, true);
      expect(notifications, 2);
      expect(iap.storePrice(PremiumTier.weekly), '99 RUB');
      expect(store.queries, 1);
      store.pending = null;
      store.price = '119 RUB';
      unawaited(
        iap.loadProducts(
          phase: ProductLoadPhase.purchase,
          purchaseTier: PremiumTier.weekly,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(store.queries, 2);
      expect(iap.storePrice(PremiumTier.weekly), '119 RUB');
    },
  );

  _testStoreWidgets('a stale native result cannot replace the newer offer', (
    tester,
  ) async {
    final oldQuery = Completer<ProductDetailsResponse>();
    store.pending = oldQuery;
    final oldResponse = store.response();
    final iap = IapService.forTesting();
    addTearDown(iap.dispose);
    unawaited(iap.loadProducts(phase: ProductLoadPhase.paywall));
    await _advance(tester, 37);
    expect(store.queries, 1);

    store.pending = null;
    store.price = '119 RUB';
    unawaited(iap.loadProducts(phase: ProductLoadPhase.paywall));
    await _advance(tester, 1);
    expect(store.queries, 2);
    expect(iap.storePrice(PremiumTier.weekly), '119 RUB');

    oldQuery.complete(oldResponse);
    await tester.pump();
    expect(iap.storePrice(PremiumTier.weekly), '119 RUB');
    expect(iap.hasCompleteStoreProducts, true);
    expect(store.queries, 2);
  });

  _testStoreWidgets('a disposed service ignores the eventual native success', (
    tester,
  ) async {
    store.pending = Completer<ProductDetailsResponse>();
    final iap = IapService.forTesting();
    unawaited(iap.loadProducts(phase: ProductLoadPhase.paywall));
    await _advance(tester, 37);
    iap.dispose();
    store.pending!.complete(store.response());
    await tester.pump();
    expect(iap.hasStoreProducts, false);
    expect(tester.takeException(), isNull);
  });
}
