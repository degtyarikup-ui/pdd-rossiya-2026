import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/iap_service.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/home/home_screen.dart';
import 'package:pdd_app/presentation/screens/profile/profile_screen.dart';
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
    'release navigation keeps the driving game and hides the unfinished games hub',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final source = ProgressDataSource();
      await source.init();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [progressDataSourceProvider.overrideWithValue(source)],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(
        bar.destinations.cast<NavigationDestination>().map(
          (item) => item.label,
        ),
        [appL10n.training, appL10n.game, appL10n.video, appL10n.profile],
      );
      expect(find.text(appL10n.navGames), findsNothing);
      // Removing the hub must not shift the profile to the game's old index.
      await tester.tap(find.text(appL10n.profile));
      await tester.pump();
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

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
