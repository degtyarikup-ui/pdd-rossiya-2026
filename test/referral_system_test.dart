import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/services/referral_service.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/l10n/gen/app_localizations.dart';
import 'package:pdd_app/presentation/screens/settings/settings_screen.dart';
import 'package:pdd_app/presentation/widgets/premium_plans_sheet.dart';
import 'package:pdd_app/presentation/widgets/referral_modal_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ru'), Locale('en'), Locale('kk')],
      locale: const Locale('ru'),
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ReferralInfo Model', () {
    test('parses from JSON correctly', () {
      final json = {
        'code': 'TEST12',
        'link': 'https://pdd-drive.app/app/?ref=TEST12',
        'invitedCount': 3,
        'rewardDays': 6,
        'hasUsedReferral': true,
        'referredBy': 'google_inviter',
        'referralCodeUsed': 'INVITE1',
        'friendBonusDays': 1,
        'inviterBonusDays': 2,
      };

      final info = ReferralInfo.fromJson(json);
      expect(info.code, 'TEST12');
      expect(info.link, 'https://pdd-drive.app/app/?ref=TEST12');
      expect(info.invitedCount, 3);
      expect(info.rewardDays, 6);
      expect(info.hasUsedReferral, true);
      expect(info.referredBy, 'google_inviter');
      expect(info.referralCodeUsed, 'INVITE1');
      expect(info.friendBonusDays, 1);
      expect(info.inviterBonusDays, 2);
    });

    test('copyWith updates fields correctly', () {
      const info = ReferralInfo(
        code: 'OLD123',
        link: 'https://pdd-drive.app/app/?ref=OLD123',
        invitedCount: 1,
        rewardDays: 2,
      );

      final updated = info.copyWith(
        code: 'NEW123',
        invitedCount: 2,
        rewardDays: 4,
        hasUsedReferral: true,
        referralCodeUsed: 'CODE99',
      );

      expect(updated.code, 'NEW123');
      expect(updated.invitedCount, 2);
      expect(updated.rewardDays, 4);
      expect(updated.hasUsedReferral, true);
      expect(updated.referralCodeUsed, 'CODE99');
    });
  });

  group('ReferralService pending code', () {
    test('savePendingCode stores code in prefs', () async {
      final service = ReferralService.instance;
      await service.savePendingCode('friendcode');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pending_referral_code'), 'FRIENDCODE');
      expect(service.pendingCode, 'FRIENDCODE');
    });

    test('claimCode validates code length before sending', () async {
      final service = ReferralService.instance;
      final res = await service.claimCode('a');
      expect(res.status, ReferralClaimStatus.invalidCode);
    });
  });

  group('ReferralModalSheet UI', () {
    testWidgets('shows sign-in prompt when unauthenticated', (tester) async {
      await tester.pumpWidget(_wrap(const Scaffold(body: ReferralModalSheet())));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('referral-sign-in-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('referral-input-field')), findsOneWidget);
      expect(find.byKey(const ValueKey('referral-activate-button')), findsOneWidget);
    });
  });

  group('Settings Screen referral button', () {
    testWidgets('renders referral tile in settings and opens sheet on tap', (tester) async {
      final data = ProgressDataSource();
      await data.init();

      final container = ProviderContainer(
        overrides: [progressDataSourceProvider.overrideWithValue(data)],
      );
      addTearDown(container.dispose);

      await container.read(appSettingsProvider.notifier).ready;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('ru'), Locale('en'), Locale('kk')],
            locale: const Locale('ru'),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final referralTile = find.byKey(const ValueKey('settings-referral-tile'));
      expect(referralTile, findsOneWidget);

      await tester.tap(referralTile);
      await tester.pumpAndSettle();

      expect(find.byType(ReferralModalSheet), findsOneWidget);
    });
  });

  group('Premium purchase menu referral button', () {
    testWidgets('renders referral button in PremiumPlansSheet and opens sheet on tap', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const Scaffold(
            body: PremiumPlansSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final referralBtn = find.byKey(const ValueKey('premium-plans-referral-button'));
      expect(referralBtn, findsOneWidget);

      await tester.tap(referralBtn);
      await tester.pumpAndSettle();

      expect(find.byType(ReferralModalSheet), findsOneWidget);
    });
  });
}
