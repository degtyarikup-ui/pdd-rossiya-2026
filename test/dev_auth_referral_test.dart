import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:pdd_app/data/services/dev_mock_endpoint.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/data/services/referral_service.dart';
import 'package:pdd_app/l10n/gen/app_localizations.dart';
import 'package:pdd_app/presentation/widgets/auth_modal_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    AuthService.setDebugSignInAvailableForTesting(true);
    await DevMockEndpoint.resetForTesting();
  });

  tearDown(() async {
    AuthService.setDebugSignInAvailableForTesting(null);
    AuthService.setDevPackageForTesting(false);
    await DevMockEndpoint.resetForTesting();
    await AuthService.instance.signOut();
  });

  test(
    'advertising code is separate from a friend code and can be replayed safely',
    () async {
      await AuthService.instance.signInDebug(
        accountId: 'dev_tester_1',
        name: 'Tester',
      );
      final service = ReferralService.instance;
      await service.getReferralInfo(forceRefresh: true);
      final first = await service.claimCode('PREMIUM7');
      expect(first.status, ReferralClaimStatus.success);
      expect(first.daysAdded, 7);
      expect(first.isReferral, false);
      expect(service.info?.hasUsedReferral, false);
      final prefs = await SharedPreferences.getInstance();
      final before = prefs.getString('dev_mock_premium_dev_tester_1');
      await service.claimCode('PREMIUM7');
      expect(prefs.getString('dev_mock_premium_dev_tester_1'), before);
      expect(
        (await service.claimCode('FRIEND26')).status,
        ReferralClaimStatus.success,
      );
    },
  );

  test('old account cannot use friend code but can use a promotion', () async {
    await AuthService.instance.signInDebug(
      accountId: 'dev_tester_1',
      name: 'Tester',
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'dev_mock_created_dev_tester_1',
      DateTime.now().subtract(const Duration(days: 8)).millisecondsSinceEpoch,
    );
    expect(
      (await ReferralService.instance.claimCode('FRIEND26')).status,
      ReferralClaimStatus.ineligible,
    );
    expect(
      (await ReferralService.instance.claimCode('PREMIUM7')).status,
      ReferralClaimStatus.success,
    );
  });

  test(
    'debugSignInAvailable is enabled by .dev package without GAME_DEBUG',
    () {
      AuthService.setDebugSignInAvailableForTesting(null);
      AuthService.setDevPackageForTesting(false);
      expect(AuthService.debugSignInAvailable, isFalse);

      AuthService.setDevPackageForTesting(true);
      expect(AuthService.debugSignInAvailable, isTrue);

      AuthService.setDevPackageForTesting(false);
    },
  );

  test(
    'dev login establishes active server session and dev session flags',
    () async {
      final auth = AuthService.instance;
      expect(auth.isAuthenticated, isFalse);
      expect(auth.hasServerSession, isFalse);

      final success = await auth.signInDebug(
        accountId: 'dev_tester_1',
        name: 'Тестировщик 1',
      );
      expect(success, isTrue);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.hasServerSession, isTrue);
      expect(auth.isDevSession, isTrue);
      expect(auth.currentUser?.id, 'dev_tester_1');
      expect(
        auth.serverHeaders['authorization'],
        startsWith('Bearer dev_token_dev_tester_1'),
      );
    },
  );

  test(
    'ReferralService.getReferralInfo receives mock referral data in dev session',
    () async {
      final auth = AuthService.instance;
      await auth.signInDebug(accountId: 'dev_tester_1', name: 'Тестировщик 1');

      final referralService = ReferralService.instance;
      final info = await referralService.getReferralInfo(forceRefresh: true);

      expect(info, isNotNull);
      expect(info!.code, 'DEVTEST1');
      expect(info.link, 'https://pdd-drive.app/app/?ref=DEVTEST1');
      expect(info.invitedCount, 0);
      expect(info.rewardDays, 0);
      expect(info.hasUsedReferral, isFalse);
    },
  );

  test(
    'ReferralService.claimCode self-referral rejected in dev session',
    () async {
      final auth = AuthService.instance;
      await auth.signInDebug(accountId: 'dev_tester_1', name: 'Тестировщик 1');

      final referralService = ReferralService.instance;
      final result = await referralService.claimCode('DEVTEST1');

      expect(result.status, ReferralClaimStatus.selfReferral);
    },
  );

  test(
    'ReferralService.claimCode non-existent code rejected in dev session',
    () async {
      final auth = AuthService.instance;
      await auth.signInDebug(accountId: 'dev_tester_1', name: 'Тестировщик 1');

      final referralService = ReferralService.instance;
      final result = await referralService.claimCode('UNKNOWN99');

      expect(result.status, ReferralClaimStatus.notFound);
    },
  );

  test(
    'ReferralService.claimCode success with seed friend code grants day and prevents duplicate',
    () async {
      final auth = AuthService.instance;
      await auth.signInDebug(accountId: 'dev_tester_1', name: 'Тестировщик 1');

      final referralService = ReferralService.instance;
      final result = await referralService.claimCode(
        DevMockEndpoint.seedFriendCode,
      );

      expect(result.status, ReferralClaimStatus.success);
      expect(result.daysAdded, 2);

      // Premium grant check
      await PremiumService.instance.checkForGrant();
      expect(PremiumService.instance.isPremium, isTrue);

      // Retry after a lost response leaves the expiry unchanged.
      final expires = PremiumService.instance.expiresAt;
      final duplicate = await referralService.claimCode(
        DevMockEndpoint.seedFriendCode,
      );
      expect(duplicate.status, ReferralClaimStatus.success);
      expect(PremiumService.instance.expiresAt, expires);
      final different = await referralService.claimCode('DEVTEST2');
      expect(different.status, ReferralClaimStatus.alreadyClaimed);
    },
  );

  test(
    'a saved invitation is never redeemed automatically on sign-in',
    () async {
      final service = ReferralService.instance;
      await service.init(incomingCode: 'friend26');
      addTearDown(service.clearPendingCodeForTesting);
      await AuthService.instance.signInDebug(accountId: 'dev_tester_1');
      final info = await service.getReferralInfo();
      expect(info?.hasUsedReferral, isFalse);
      expect(PremiumService.instance.isPremium, isFalse);
      expect(service.pendingCode, 'FRIEND26');
    },
  );

  test('Peer referral flow between tester 1 and tester 2', () async {
    final auth = AuthService.instance;
    final referralService = ReferralService.instance;

    // 1. Tester 1 logs in and checks code
    await auth.signInDebug(accountId: 'dev_tester_1', name: 'Тестировщик 1');
    final info1 = await referralService.getReferralInfo(forceRefresh: true);
    expect(info1?.code, 'DEVTEST1');
    expect(info1?.invitedCount, 0);

    // 2. Switch to Tester 2
    await auth.signOut();
    await auth.signInDebug(accountId: 'dev_tester_2', name: 'Тестировщик 2');
    final info2 = await referralService.getReferralInfo(forceRefresh: true);
    expect(info2?.code, 'DEVTEST2');

    // 3. Tester 2 claims Tester 1's code
    final claimRes = await referralService.claimCode('DEVTEST1');
    expect(claimRes.status, ReferralClaimStatus.success);

    // Tester 2 has Premium now
    await PremiumService.instance.checkForGrant();
    expect(PremiumService.instance.isPremium, isTrue);

    // 4. Switch back to Tester 1, check that inviter was rewarded
    await auth.signOut();
    await auth.signInDebug(accountId: 'dev_tester_1', name: 'Тестировщик 1');
    expect(
      PremiumService.instance.isPremium,
      isTrue,
      reason: 'signInDebug should sync premium state from dev mock',
    );
    final updatedInfo1 = await referralService.getReferralInfo(
      forceRefresh: true,
    );
    expect(updatedInfo1?.invitedCount, 1);
    expect(updatedInfo1?.rewardDays, 2);

    // Tester 1 also received Premium reward
    await PremiumService.instance.checkForGrant();
    expect(PremiumService.instance.isPremium, isTrue);
  });

  test('deleteAccount works and purges mock data in dev session', () async {
    final auth = AuthService.instance;
    await auth.signInDebug(accountId: 'dev_tester_1', name: 'Тестировщик 1');
    expect(auth.isAuthenticated, isTrue);
    expect(auth.isDevSession, isTrue);

    final referralService = ReferralService.instance;
    final info = await referralService.getReferralInfo(forceRefresh: true);
    expect(info?.code, 'DEVTEST1');

    final deleted = await auth.deleteAccount();
    expect(deleted, isTrue);
    expect(auth.isAuthenticated, isFalse);
    expect(auth.currentUser, isNull);
    expect(auth.hasServerSession, isFalse);
  });

  testWidgets(
    'AuthModalSheet renders dev login button and signs in through account picker',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: AuthModalSheet()),
        ),
      );
      await tester.pumpAndSettle();

      final buttonFinder = find.byKey(const ValueKey('dev-mock-login-button'));
      expect(buttonFinder, findsOneWidget);

      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('dev-account-tester-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('dev-account-tester-2')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('dev-account-tester-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(AuthService.instance.isAuthenticated, isTrue);
      expect(AuthService.instance.hasServerSession, isTrue);
      expect(AuthService.instance.currentUser?.id, 'dev_tester_1');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 7));
    },
  );
}
