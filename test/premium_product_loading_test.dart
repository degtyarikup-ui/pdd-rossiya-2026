import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
// ignore: depend_on_referenced_packages
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/premium_plans_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PriceStore extends InAppPurchasePlatform {
  int queries = 0;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    queries++;
    return ProductDetailsResponse(
      productDetails: [
        ProductDetails(
          id: 'ru.pdd.pddapp.sub.week',
          title: 'Week',
          description: 'Week',
          price: '99 ₽',
          rawPrice: 99,
          currencyCode: 'RUB',
        ),
        ProductDetails(
          id: 'ru.pdd.pddapp.sub.3months',
          title: 'Quarter',
          description: 'Quarter',
          price: '290 ₽',
          rawPrice: 290,
          currencyCode: 'RUB',
        ),
      ],
      notFoundIDs: const [],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PriceStore store;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    InAppPurchase.instance;
    store = PriceStore();
    InAppPurchasePlatform.instance = store;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('pdd/device_region'),
          (_) async => 'RU',
        );
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    updateAppLocale(const Locale('ru'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('pdd/device_region'),
          null,
        );
  });
  for (final language in ['ru', 'en', 'kk']) {
    testWidgets(
      'SBP opening in $language does not query Play; selecting Play queries prices',
      (tester) async {
        try {
          updateAppLocale(Locale(language));
          await tester.binding.setSurfaceSize(const Size(800, 1600));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            const MaterialApp(home: Scaffold(body: PremiumPlansSheet())),
          );
          await tester.pumpAndSettle();
          expect(store.queries, 0);
          final play = find.text(appL10n.paywallStoreGoogle);
          await tester.ensureVisible(play);
          await tester.tap(play);
          await tester.pumpAndSettle();
          expect(store.queries, 1);
          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
}
