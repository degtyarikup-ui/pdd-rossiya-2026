import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
// Replace only the native store boundary; exercise the real payment services.
// ignore: depend_on_referenced_packages
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/iap_service.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/premium_benefits_screen.dart';
import 'package:pdd_app/presentation/widgets/premium_paywall_sheet.dart';
import 'package:pdd_app/presentation/widgets/premium_plans_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PendingStore extends InAppPurchasePlatform {
  final updates = StreamController<List<PurchaseDetails>>.broadcast();
  final completed = <String?>[];
  final products = [
    ProductDetails(
      id: 'ru.pdd.pddApp.sub.3months',
      title: 'Quarter',
      description: 'Quarter',
      price: '290 ₽',
      rawPrice: 290,
      currencyCode: 'RUB',
    ),
    ProductDetails(
      id: 'u.pdd.pddApp.premium.week',
      title: 'Week',
      description: 'Week',
      price: '99 ₽',
      rawPrice: 99,
      currencyCode: 'RUB',
    ),
  ];
  final purchases = <PurchaseParam>[];

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async =>
      ProductDetailsResponse(productDetails: products, notFoundIDs: []);

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    purchases.add(purchaseParam);
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed.add(purchase.purchaseID);
  }

  void confirm() {
    updates.add([
      PurchaseDetails(
        purchaseID: 'busy-plan-purchase',
        productID: products.first.id,
        verificationData: PurchaseVerificationData(
          localVerificationData: '',
          serverVerificationData: 'verified-test-receipt',
          source: 'app_store',
        ),
        transactionDate: '0',
        status: PurchaseStatus.purchased,
      )..pendingCompletePurchase = true,
    ]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'pending store purchase locks plans and verified success closes both routes',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      InAppPurchase.instance;
      final store = _PendingStore();
      InAppPurchasePlatform.instance = store;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final iap = IapService.instance;
      final expiry = DateTime.now().toUtc().add(const Duration(days: 90));
      final user = UserProfile(
        id: 'apple_busy_test',
        name: 'Test',
        email: 'test@example.com',
        provider: AuthProviderType.apple,
        createdAt: DateTime(2026),
      );
      SharedPreferences.setMockInitialValues({
        'auth_user_profile': user.toJson(),
      });
      FlutterSecureStorage.setMockInitialValues({
        'pdd_server_session': jsonEncode({
          'userId': user.id,
          'token': 'test-session',
          'expiresAt': expiry.toIso8601String(),
        }),
      });
      final verification = Completer<http.Response>();
      var verificationStarted = false;
      var gateCompleted = false;
      bool? gateResult;

      Future<void> pumpUntil(bool Function() ready) async {
        for (var i = 0; i < 50 && !ready(); i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(ready(), isTrue);
      }

      try {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await http.runWithClient(
          () async {
            await PremiumService.instance.init();
            await AuthService.instance.init();
            await iap.init();
            expect(AuthService.instance.hasServerSession, isTrue);
            await tester.pumpWidget(
              MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () async {
                        gateResult = await PremiumPaywallSheet.show(context);
                        gateCompleted = true;
                      },
                      child: const Text('Open premium'),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('Open premium'));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const ValueKey('premium-show-plans')));
            await tester.pumpAndSettle();
            final purchase = find.byKey(
              const ValueKey('premium-plans-purchase'),
            );
            await tester.ensureVisible(purchase);
            await tester.pumpAndSettle();

            // Both taps reach the original callback before the disabled
            // button has rebuilt; the operation guard must reject the second.
            await tester.tap(purchase);
            await tester.tap(purchase);
            await pumpUntil(() => store.purchases.isNotEmpty);
            expect(store.purchases, hasLength(1));
            expect(
              store.purchases.single.productDetails.id,
              IapService.productId3Months,
            );
            expect(tester.widget<ElevatedButton>(purchase).onPressed, isNull);
            expect(
              tester
                  .widget<IconButton>(
                    find.byKey(const ValueKey('premium-plans-close')),
                  )
                  .onPressed,
              isNull,
            );
            for (final tier in PremiumTier.values) {
              final card = find.byKey(ValueKey('premium-plan-${tier.name}'));
              final tap = find.descendant(
                of: card,
                matching: find.byType(InkWell),
              );
              expect(tester.widget<InkWell>(tap).onTap, isNull);
            }
            expect(
              tester
                  .widget<TextButton>(
                    find.widgetWithText(TextButton, appL10n.paywallRestore),
                  )
                  .onPressed,
              isNull,
            );

            await tester.binding.handlePopRoute();
            await tester.pump();
            await tester.tapAt(const Offset(2, 2));
            await tester.pump();
            expect(find.byType(PremiumPlansSheet), findsOneWidget);
            expect(gateCompleted, isFalse);

            store.confirm();
            await pumpUntil(() => verificationStarted);
            expect(find.byType(PremiumPlansSheet), findsOneWidget);
            expect(PremiumService.instance.isPremium, isFalse);
            verification.complete(
              http.Response(
                jsonEncode({
                  'ok': true,
                  'isPremium': true,
                  'premiumExpiresAt': expiry.toIso8601String(),
                }),
                200,
              ),
            );
            await pumpUntil(() => gateCompleted);
            await tester.pumpAndSettle();
            expect(gateResult, isTrue);
            expect(PremiumService.instance.isPremium, isTrue);
            expect(store.purchases, hasLength(1));
            expect(store.completed, ['busy-plan-purchase']);
            expect(find.byType(PremiumPlansSheet), findsNothing);
            expect(find.byType(PremiumBenefitsScreen), findsNothing);
            expect(find.byType(PremiumPaywallSheet), findsNothing);
            expect(tester.takeException(), isNull);
            await tester.pump(const Duration(seconds: 4));
            await tester.pumpAndSettle();
          },
          () => MockClient((request) async {
            switch (request.url.path) {
              case '/api/user/store/status':
                return http.Response('{"configured":true}', 200);
              case '/api/user/store/account-token':
                return http.Response(
                  '{"accountToken":"11111111-1111-5111-8111-111111111111"}',
                  200,
                );
              case '/api/user/purchase':
                verificationStarted = true;
                return verification.future;
              default:
                return http.Response('{"ok":true,"isPremium":false}', 200);
            }
          }),
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        iap.dispose();
        await store.updates.close();
        debugDefaultTargetPlatformOverride = null;
        updateAppLocale(const Locale('ru'));
      }
    },
  );
}
