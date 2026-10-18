import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/game/godot_game.dart';
import 'package:pdd_app/presentation/screens/games/games_hub_screen.dart';
import 'package:pdd_app/presentation/screens/games/games_hub_view.dart';
import 'package:pdd_app/presentation/widgets/auth_modal_sheet.dart';
import 'package:pdd_app/presentation/widgets/sign_in_required_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final signedIn = StateProvider<bool>((ref) => false);
  late ProgressDataSource progress;
  late List<String> gameCalls;

  setUpAll(() async {
    final fonts = FontLoader(AppTheme.fontFamily);
    for (final weight in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
    ]) {
      fonts.addFont(rootBundle.load('assets/fonts/Onest-$weight.ttf'));
    }
    await fonts.load();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    progress = ProgressDataSource();
    await progress.init();
    GodotGame.resetForTest();
    HapticFeedbackHelper.setEnabled(false);
    gameCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('pdd/godot_game'), (
          call,
        ) async {
          gameCalls.add(call.method);
          return call.method == 'available' ? false : null;
        });
  });

  tearDown(() {
    HapticFeedbackHelper.setEnabled(true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('pdd/godot_game'), null);
  });

  Future<ProviderContainer> open(
    WidgetTester tester, {
    String language = 'ru',
  }) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isAuthenticatedProvider.overrideWith((ref) => ref.watch(signedIn)),
          isPremiumProvider.overrideWithValue(false),
          progressDataSourceProvider.overrideWithValue(progress),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: const GamesHubScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(GamesHubScreen)),
    );
  }

  for (final language in ['ru', 'en', 'kk']) {
    testWidgets('Guest must sign in before opening games ($language)', (
      tester,
    ) async {
      await open(tester, language: language);
      expect(find.byType(SignInRequiredView), findsOneWidget);
      expect(find.byType(GamesHubView), findsNothing);
      expect(find.text(appL10n.gameLockedTitle), findsOneWidget);
      expect(gameCalls, isEmpty);
      await tester.ensureVisible(find.text(appL10n.feedSignIn));
      await tester.tap(find.text(appL10n.feedSignIn));
      await tester.pumpAndSettle();
      expect(find.byType(AuthModalSheet), findsOneWidget);
      expect(find.byType(GamesHubView), findsNothing);
      expect(gameCalls, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Sign-in opens free games; sign-out removes access immediately', (
    tester,
  ) async {
    final container = await open(tester);
    container.read(signedIn.notifier).state = true;
    await tester.pumpAndSettle();
    expect(find.byType(SignInRequiredView), findsNothing);
    expect(find.byType(GamesHubView), findsOneWidget);
    expect(container.read(isPremiumProvider), isFalse);

    await tester.scrollUntilVisible(
      find.text(appL10n.gameTrafficControllerTitle),
      200,
    );
    await tester.tapAt(
      tester.getCenter(find.text(appL10n.gameTrafficControllerTitle)),
    );
    await tester.pumpAndSettle();
    expect(gameCalls, contains('available'));
    expect(find.text(appL10n.gameUnavailable), findsOneWidget);

    container.read(signedIn.notifier).state = false;
    await tester.pumpAndSettle();
    expect(find.byType(SignInRequiredView), findsOneWidget);
    expect(find.byType(GamesHubView), findsNothing);
    final callsBefore = gameCalls.length;
    await tester.pump(const Duration(minutes: 2));
    expect(gameCalls.length, callsBefore);

    container.read(signedIn.notifier).state = true;
    await tester.pumpAndSettle();
    expect(find.byType(GamesHubView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
