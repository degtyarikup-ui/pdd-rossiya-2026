import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
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
      expect(info.referralCodeUsed, 'INVITE1');
      expect(info.friendBonusDays, 1);
      expect(info.inviterBonusDays, 2);
    });

    test('shares only the canonical invitation URL', () {
      final info = ReferralInfo.fromJson({
        'code': 'JSON456',
        'link': 'https://example.com',
      });
      expect(info.link, 'https://pdd-drive.app/app/?ref=JSON456');
      expect(
        referralCodeFromInput('  https://pdd-drive.app/app/?ref=json456  '),
        'JSON456',
      );
      expect(
        referralCodeFromInput(
          'https://pdd-drive.app.example.com/app/?ref=JSON456',
        ),
        isNull,
      );
      expect(referralCodeFromInput('JSON-456'), isNull);
    });
  });

  group('ReferralService pending code', () {
    test('savePendingCode stores code in prefs', () async {
      final service = ReferralService.instance;
      await service.savePendingCode('friendcode');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pending_referral_code'), 'FRIENDCODE');
      expect(service.pendingCode, 'FRIENDCODE');
      await service.clearPendingCodeForTesting();
    });

    test('claimCode validates code length before sending', () async {
      final service = ReferralService.instance;
      final res = await service.claimCode('a');
      expect(res.status, ReferralClaimStatus.invalidCode);
    });
  });

  group('ReferralModalSheet UI', () {
    tearDown(() async {
      AuthService.instance.setSessionForTesting(
        user: null,
        token: null,
        expiresAt: null,
      );
      ReferralService.instance.setInfoForTesting(null);
      ReferralService.instance.mockGetReferralInfo = null;
      await ReferralService.instance.clearPendingCodeForTesting();
    });

    testWidgets('shows sign-in and lets guests enter a code', (tester) async {
      AuthService.instance.setSessionForTesting(
        user: null,
        token: null,
        expiresAt: null,
      );
      ReferralService.instance.setInfoForTesting(null);
      ReferralService.instance.mockGetReferralInfo = null;
      await ReferralService.instance.clearPendingCodeForTesting();

      await tester.pumpWidget(
        _wrap(const Scaffold(body: ReferralModalSheet())),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('referral-sign-in-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('referral-input-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('referral-activate-button')),
        findsOneWidget,
      );
      expect(find.text('Один код на аккаунт'), findsOneWidget);
    });

    testWidgets(
      'shows retry button when authenticated session has no info and is not loading',
      (tester) async {
        final user = UserProfile(
          id: 'google_retry_user',
          name: 'Retry User',
          email: 'retry@example.com',
          provider: AuthProviderType.google,
          createdAt: DateTime(2026),
        );
        AuthService.instance.setSessionForTesting(
          user: user,
          token: 'test-token',
          expiresAt: DateTime.now().add(const Duration(days: 30)),
        );
        ReferralService.instance.setInfoForTesting(null);
        var attempts = 0;
        ReferralService.instance.mockGetReferralInfo =
            ({bool forceRefresh = false}) async {
              attempts++;
              return null;
            };

        await tester.pumpWidget(
          _wrap(const Scaffold(body: ReferralModalSheet())),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('referral-retry-button')),
          findsOneWidget,
        );
        expect(find.text('Не удалось загрузить ваш код'), findsOneWidget);
        expect(attempts, 1);

        await tester.tap(find.byKey(const ValueKey('referral-retry-button')));
        await tester.pumpAndSettle();
        expect(attempts, 2);
      },
    );

    testWidgets('auto-populates input field when pending code is set', (
      tester,
    ) async {
      AuthService.instance.setSessionForTesting(
        user: null,
        token: null,
        expiresAt: null,
      );
      ReferralService.instance.setInfoForTesting(null);
      await ReferralService.instance.savePendingCode('FRIEND77');

      await tester.pumpWidget(
        _wrap(const Scaffold(body: ReferralModalSheet())),
      );
      await tester.pumpAndSettle();

      final inputFinder = find.byKey(const ValueKey('referral-input-field'));
      expect(inputFinder, findsOneWidget);
      final textField = tester.widget<TextField>(inputFinder);
      expect(textField.controller?.text, 'FRIEND77');
      await ReferralService.instance.clearPendingCodeForTesting();
    });

    testWidgets('shows the code and lets the user copy the exact link', (
      tester,
    ) async {
      final user = UserProfile(
        id: 'google_test',
        name: 'Tester',
        email: 't@example.com',
        provider: AuthProviderType.google,
        createdAt: DateTime(2026),
      );
      AuthService.instance.setSessionForTesting(
        user: user,
        token: 'test-token',
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      );
      ReferralService.instance.setInfoForTesting(
        const ReferralInfo(code: 'MYCODE9', invitedCount: 2, rewardDays: 4),
      );

      await tester.pumpWidget(
        _wrap(const Scaffold(body: ReferralModalSheet())),
      );
      await tester.pumpAndSettle();

      // Sign-in prompt should NOT be visible
      expect(
        find.byKey(const ValueKey('referral-sign-in-button')),
        findsNothing,
      );

      expect(find.text('MYCODE9'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('referral-share-button')),
        findsOneWidget,
      );
      final clipboard = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('referral-copy-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('referral-copy-link-button')));
      await tester.pumpAndSettle();
      expect(clipboard, ['MYCODE9', 'https://pdd-drive.app/app/?ref=MYCODE9']);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('a late response never reveals the previous account code', (
      tester,
    ) async {
      final service = ReferralService.instance;
      final first = Completer<ReferralInfo?>();
      void signIn(String id) {
        AuthService.instance.setSessionForTesting(
          user: UserProfile(
            id: id,
            name: id,
            email: '',
            provider: AuthProviderType.google,
            createdAt: DateTime(2026),
          ),
          token: id,
          expiresAt: DateTime.now().add(const Duration(days: 1)),
        );
      }

      signIn('google_first');
      service.mockGetReferralInfo = ({bool forceRefresh = false}) async =>
          AuthService.instance.currentUser?.id == 'google_first'
          ? first.future
          : const ReferralInfo(code: 'CURRENT1');
      await tester.pumpWidget(
        _wrap(const Scaffold(body: ReferralModalSheet())),
      );
      await tester.pump();
      signIn('google_second');
      await tester.pumpAndSettle();
      first.complete(const ReferralInfo(code: 'PRIVATE1'));
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE1'), findsNothing);
      expect(find.text('CURRENT1'), findsOneWidget);
    });
  });

  group('Settings Screen referral button', () {
    testWidgets('renders referral tile in settings and opens sheet on tap', (
      tester,
    ) async {
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
      await tester.scrollUntilVisible(referralTile, 200);
      await tester.ensureVisible(referralTile);
      await tester.pumpAndSettle();
      expect(referralTile, findsOneWidget);

      await tester.tap(referralTile);
      await tester.pumpAndSettle();

      expect(find.byType(ReferralModalSheet), findsOneWidget);
    });
  });

  group('Premium purchase menu referral button', () {
    testWidgets(
      'renders referral button in PremiumPlansSheet and opens sheet on tap',
      (tester) async {
        await tester.pumpWidget(
          _wrap(const Scaffold(body: PremiumPlansSheet())),
        );
        await tester.pumpAndSettle();

        final referralBtn = find.byKey(
          const ValueKey('premium-plans-referral-button'),
        );
        expect(referralBtn, findsOneWidget);

        await tester.tap(referralBtn);
        await tester.pumpAndSettle();

        expect(find.byType(ReferralModalSheet), findsOneWidget);

        final closeBtn = find.byKey(const ValueKey('referral-close-button'));
        expect(closeBtn, findsOneWidget);
        await tester.tap(closeBtn);
        await tester.pumpAndSettle();

        expect(find.byType(ReferralModalSheet), findsNothing);
      },
    );
  });
}
