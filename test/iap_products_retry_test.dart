import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
// The fake replaces the store boundary while exercising the real service.
// ignore: depend_on_referenced_packages
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:pdd_app/data/services/iap_service.dart';

/// Магазин, который первые [failures] запросов тарифов отвечает ошибкой.
class FlakyProductStore extends InAppPurchasePlatform {
  FlakyProductStore({required this.failures});

  final int failures;
  int queries = 0;
  final product = ProductDetails(
    id: 'u.pdd.pddApp.premium.week',
    title: 'Week',
    description: 'Week',
    price: '99 ₽',
    rawPrice: 99,
    currencyCode: 'RUB',
  );

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => const Stream.empty();

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    queries++;
    if (queries <= failures) {
      return ProductDetailsResponse(
        productDetails: const [],
        notFoundIDs: const [],
        error: IAPError(
          source: 'test',
          code: 'channel-error',
          message: 'temporary',
        ),
      );
    }
    return ProductDetailsResponse(
      productDetails: [product],
      notFoundIDs: const [],
    );
  }
}

/// Подменяет магазин. Обёртку создаём до подмены: при первом обращении она
/// сама регистрирует нативный магазин, и подмена бы перезаписалась.
void useStore(InAppPurchasePlatform store) {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  InAppPurchase.instance;
  InAppPurchasePlatform.instance = store;
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => IapService.productRetryUnit = Duration.zero);

  test('тарифы загружаются со второй попытки после сбоя магазина', () async {
    final store = FlakyProductStore(failures: 1);
    useStore(store);

    await IapService.instance.loadProducts();

    expect(store.queries, 2);
    expect(
      IapService.instance.products.keys,
      contains('u.pdd.pddApp.premium.week'),
    );
  });

  test('параллельные вызовы загрузки делят один запрос к магазину', () async {
    final store = FlakyProductStore(failures: 0);
    useStore(store);

    await Future.wait([
      IapService.instance.loadProducts(),
      IapService.instance.loadProducts(),
    ]);

    expect(store.queries, 1);
  });
}
