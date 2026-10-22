import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
// The fake replaces the store boundary while exercising the real service.
// ignore: depend_on_referenced_packages
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:pdd_app/data/services/iap_service.dart';
import 'package:pdd_app/presentation/widgets/premium_plans_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App Store, который сначала не отдаёт тарифы, а потом начинает.
class SilentStore extends InAppPurchasePlatform {
  bool selling = false;
  int queries = 0;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => const Stream.empty();

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    queries++;
    return ProductDetailsResponse(
      productDetails: [
        if (selling)
          ProductDetails(
            id: IapService.productId3Months,
            title: '3 months',
            description: '3 months',
            price: '290,00 ₽',
            rawPrice: 290,
            currencyCode: 'RUB',
          ),
      ],
      notFoundIDs: const [],
    );
  }
}

void main() {
  late SilentStore store;
  final placeholder = find.byKey(const ValueKey('price-placeholder'));

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    InAppPurchase.instance;
    store = SilentStore();
    InAppPurchasePlatform.instance = store;
    IapService.productRetryUnit = Duration.zero;
    IapService.instance.products.clear();
    IapService.instance.debugClearPriceCache();
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    IapService.instance.products.clear();
  });

  Future<void> openPaywall(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PremiumPlansSheet())),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets(
    'iOS: пока магазин молчит — заглушка вместо прочерка, цены догружаются сами',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await openPaywall(tester);

      expect(find.text('—'), findsNothing);
      expect(placeholder, findsNWidgets(2));
      final first = store.queries;
      expect(first, greaterThan(0));

      // Экран открыт: через паузу магазин спрашивается снова, без ошибок.
      store.selling = true;
      await tester.pump(const Duration(seconds: 21));
      await tester.pump(const Duration(seconds: 1));
      expect(store.queries, greaterThan(first));
      expect(find.text('290,00 ₽'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Закрытый экран больше не спрашивает магазин.
      await tester.pumpWidget(const SizedBox());
      final closed = store.queries;
      await tester.pump(const Duration(seconds: 60));
      expect(store.queries, closed);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('iOS: прошлая цена магазина видна сразу, пока он не ответил', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'iap_store_prices': jsonEncode({'threeMonths': '2 990 ₸'}),
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await IapService.instance.init();
    await openPaywall(tester);

    expect(find.text('2 990 ₸'), findsOneWidget);
    // Недельной цены магазин ещё не называл — на её месте заглушка.
    expect(placeholder, findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
