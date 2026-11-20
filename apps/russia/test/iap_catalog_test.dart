import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
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

List<GooglePlayProductDetails> playQuarter(
  String id,
  int price, {
  bool withTrial = false,
  String trialPeriod = 'P3D',
  String token = 'token',
}) {
  final renewal = PricingPhaseWrapper(
    billingCycleCount: 0,
    billingPeriod: 'P3M',
    formattedPrice: '€$price',
    priceAmountMicros: price * 1000000,
    priceCurrencyCode: 'EUR',
    recurrenceMode: RecurrenceMode.infiniteRecurring,
  );
  return GooglePlayProductDetails.fromProductDetails(
    ProductDetailsWrapper(
      productId: id,
      productType: ProductType.subs,
      description: id,
      name: id,
      title: id,
      subscriptionOfferDetails: [
        if (withTrial)
          SubscriptionOfferDetailsWrapper(
            basePlanId: 'quarter',
            offerId: 'trial-3-days',
            offerTags: [],
            offerIdToken: token,
            pricingPhases: [
              PricingPhaseWrapper(
                billingCycleCount: 1,
                billingPeriod: trialPeriod,
                formattedPrice: 'Free',
                priceAmountMicros: 0,
                priceCurrencyCode: 'EUR',
                recurrenceMode: RecurrenceMode.finiteRecurring,
              ),
              renewal,
            ],
          ),
        SubscriptionOfferDetailsWrapper(
          basePlanId: 'quarter',
          offerTags: [],
          offerIdToken: 'regular',
          pricingPhases: [renewal],
        ),
      ],
    ),
  );
}

AppStoreProduct2Details appleQuarter(
  String id,
  int days, {
  String group = 'premium',
}) => AppStoreProduct2Details.fromSK2Product(
  SK2Product(
    id: id,
    displayName: id,
    displayPrice: '€4',
    description: id,
    price: 4,
    type: SK2ProductType.autoRenewable,
    priceLocale: SK2PriceLocale(currencyCode: 'EUR', currencySymbol: '€'),
    subscription: SK2SubscriptionInfo(
      subscriptionGroupID: group,
      subscriptionPeriod: const SK2SubscriptionPeriod(
        value: 3,
        unit: SK2SubscriptionPeriodUnit.month,
      ),
      promotionalOffers: [
        if (days > 0)
          SK2SubscriptionOffer(
            type: SK2SubscriptionOfferType.introductory,
            period: SK2SubscriptionPeriod(
              value: days,
              unit: SK2SubscriptionPeriodUnit.day,
            ),
            periodCount: 1,
            paymentMode: SK2SubscriptionOfferPaymentMode.freeTrial,
            price: 0,
          ),
      ],
    ),
  ),
);

class CatalogStore extends InAppPurchasePlatform {
  final requests = <Set<String>>[];
  List<ProductDetails> products = [];
  IAPError? error;
  PurchaseParam? launched;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => const Stream.empty();
  int availabilityFailures = 0;
  int availabilityChecks = 0;
  @override
  Future<bool> isAvailable() async =>
      ++availabilityChecks > availabilityFailures;
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

  test(
    'store reconnects before products load and unavailable store stays bounded',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      store.availabilityFailures = 1;
      store.products = [
        product('u.pdd.pddApp.premium.week'),
        product('ru.pdd.pddApp.sub.3months'),
      ];
      final iap = IapService.forTesting();
      addTearDown(iap.dispose);
      await iap.loadProducts(phase: ProductLoadPhase.paywall);
      expect(store.availabilityChecks, 2);
      expect(iap.hasCompleteStoreProducts, true);
      store.availabilityChecks = 0;
      store.availabilityFailures = 100;
      final unavailable = IapService.forTesting();
      addTearDown(unavailable.dispose);
      await unavailable.loadProducts(phase: ProductLoadPhase.paywall);
      expect(store.availabilityChecks, 3);
      expect(unavailable.isAvailable, false);
    },
  );

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
    'Play chooses the exact eligible offer and always displays its renewing price',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      DeviceRegion.readPlayCountry = () async => 'DE';
      addTearDown(DeviceRegion.resetPlayCountry);
      NativeOfferPolicy policy = (standard: true, trial: true);
      final iap = IapService.forTesting(readPolicy: (_) async => policy);
      addTearDown(iap.dispose);
      final legacy = IapService.productId3Months;
      final standard = IapService.productIdQuarterStandard;
      final trial = IapService.productIdQuarterTrial;
      final week = product(IapService.productIdWeek);
      List<ProductDetails> catalog({
        int price = 4,
        String period = 'P3D',
        bool eligible = true,
      }) => [
        week,
        ...playQuarter(legacy, 3),
        ...playQuarter(standard, 4),
        ...playQuarter(trial, price, withTrial: eligible, trialPeriod: period),
      ];
      store.products = catalog();
      await iap.loadProducts();
      final offer = iap.storeOffer(PremiumTier.threeMonths)!;
      expect(offer.hasTrial, isTrue);
      expect(offer.renewalPrice, '€4');
      expect((offer.product as GooglePlayProductDetails).offerToken, 'token');
      expect(iap.storePrice(PremiumTier.threeMonths), '€4');
      for (final invalid in [
        catalog(price: 9),
        catalog(period: 'P7D'),
        catalog(eligible: false),
      ]) {
        store.products = invalid;
        await iap.loadProducts();
        expect(iap.storeOffer(PremiumTier.threeMonths)!.hasTrial, isFalse);
        expect(iap.storeOffer(PremiumTier.threeMonths)!.product.id, standard);
      }
      store.products = [week, ...playQuarter(legacy, 3)];
      await iap.loadProducts();
      expect(iap.hasCompleteStoreProducts, isTrue);
      expect(iap.storePrice(PremiumTier.threeMonths), '€3');
      store.products = catalog();
      policy = (standard: false, trial: false);
      await iap.loadProducts();
      expect(store.requests.last, {IapService.productIdWeek, legacy});
      expect(iap.storePrice(PremiumTier.threeMonths), '€3');
      expect(iap.storeOffer(PremiumTier.threeMonths)!.hasTrial, isFalse);
      final legacyTrial = IapService.productIdQuarterLegacyTrial;
      store.products = [
        ...catalog(),
        ...playQuarter(legacyTrial, 3, withTrial: true),
      ];
      policy = (standard: false, trial: true);
      await iap.loadProducts();
      final promoTrial = iap.storeOffer(PremiumTier.threeMonths)!;
      expect(promoTrial.product.id, legacyTrial);
      expect(promoTrial.hasTrial, isTrue);
      expect(promoTrial.renewalPrice, '€3');
      expect(store.requests.last, isNot(contains(trial)));
      DeviceRegion.resetPlayCountry();
      DeviceRegion.readPlayCountry = () async => 'RU';
      policy = (standard: true, trial: true);
      await iap.loadProducts();
      expect(store.requests.last, isNot(contains(trial)));
    },
  );

  test(
    'StoreKit requires a matching 3-day intro plus account eligibility',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      bool eligible = true;
      final iap = IapService.forTesting(
        readPolicy: (_) async => (standard: true, trial: true),
        appleEligible: (_) async => eligible,
      );
      addTearDown(iap.dispose);
      void setDays(int days, {String group = 'premium'}) {
        store.products = [
          product(IapService.productIdWeek),
          appleQuarter(IapService.productId3Months, 0),
          appleQuarter(IapService.productIdQuarterStandard, 0),
          appleQuarter(IapService.productIdQuarterTrial, days, group: group),
        ];
      }

      setDays(3);
      await iap.loadProducts();
      expect(iap.storeOffer(PremiumTier.threeMonths)!.hasTrial, isTrue);
      eligible = false;
      await iap.loadProducts();
      expect(iap.storeOffer(PremiumTier.threeMonths)!.hasTrial, isFalse);
      eligible = true;
      setDays(7);
      await iap.loadProducts();
      expect(iap.storeOffer(PremiumTier.threeMonths)!.hasTrial, isFalse);
      setDays(3, group: 'unrelated');
      await iap.loadProducts();
      expect(iap.storeOffer(PremiumTier.threeMonths)!.hasTrial, isFalse);
    },
  );

  test(
    'a trial click can never purchase the paid fallback after refresh',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      DeviceRegion.readPlayCountry = () async => 'DE';
      addTearDown(DeviceRegion.resetPlayCountry);
      final profile = UserProfile(
        id: 'google_trial',
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
      await http.runWithClient(
        () async {
          await AuthService.instance.init();
          final iap = IapService.forTesting(
            readPolicy: (_) async => (standard: true, trial: true),
            queryPlayPurchases: () async =>
                QueryPurchaseDetailsResponse(pastPurchases: []),
          );
          addTearDown(iap.dispose);
          final standard = playQuarter(IapService.productIdQuarterStandard, 4);
          final trial = IapService.productIdQuarterTrial;
          store.products = [
            ...standard,
            ...playQuarter(trial, 4, withTrial: true),
            product(IapService.productIdWeek),
          ];
          await iap.loadProducts();
          final displayed = iap.storeOffer(PremiumTier.threeMonths)!;
          store.products = [
            ...standard,
            ...playQuarter(trial, 4),
            product(IapService.productIdWeek),
          ];
          expect(
            await iap.buyProduct(
              PremiumTier.threeMonths,
              expectedOffer: displayed,
            ),
            PurchaseResult.offerChanged,
          );
          expect(store.launched, isNull);
          store.products = [
            ...standard,
            ...playQuarter(trial, 4, withTrial: true, token: 'fresh'),
            product(IapService.productIdWeek),
          ];
          await iap.buyProduct(
            PremiumTier.threeMonths,
            expectedOffer: displayed,
          );
          final launched = store.launched;
          expect(
            (launched?.productDetails as GooglePlayProductDetails).offerToken,
            'fresh',
          );
          expect(launched?.applicationUserName, isNotEmpty);
        },
        () =>
            MockClient((_) async => http.Response('{"configured":true}', 200)),
      );
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
