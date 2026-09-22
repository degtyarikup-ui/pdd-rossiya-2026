import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/iap_service.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/presentation/widgets/auth_modal_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('disabled debug login cannot restore a cached test account', () async {
    SharedPreferences.setMockInitialValues({
      'auth_user_profile': UserProfile(
        id: 'debug_tester',
        name: 'Tester',
        email: 'tester@example.com',
        provider: AuthProviderType.google,
        createdAt: DateTime(2026),
      ).toJson(),
    });
    expect(AuthService.debugSignInAvailable, isFalse);
    await AuthService.instance.init();
    expect(AuthService.instance.isAuthenticated, isFalse);
    expect(await AuthService.instance.signInDebug(), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('auth_user_profile'), isFalse);
  });

  test('a single weekly product is never offered as three months', () {
    final service = IapService.instance;
    service.products.clear();
    service.products[IapService.productIdWeek] = ProductDetails(
      id: IapService.productIdWeek,
      title: 'Week',
      description: 'Week',
      price: 'WEEK_PRICE',
      rawPrice: 1,
      currencyCode: 'USD',
    );
    expect(
      service.getProductPrice(PremiumTier.threeMonths, 'UNAVAILABLE'),
      'UNAVAILABLE',
    );
    expect(
      service.getProductPrice(PremiumTier.weekly, 'UNAVAILABLE'),
      'WEEK_PRICE',
    );
    service.products.clear();
  });

  testWidgets(
    'auth sheet fits a small screen with large text and no debug button',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(body: AuthModalSheet()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.bug_report_outlined), findsNothing);
    },
  );
}
