import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/games/games_hub_view.dart';

const _cardKeys = [
  'games-card-parking',
  'games-card-signs',
  'games-card-regulator',
  'games-card-crossroads',
  'games-card-city',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  tearDown(() => updateAppLocale(const Locale('ru')));

  Future<GlobalKey> open(
    WidgetTester tester, {
    Size size = const Size(390, 760),
    EdgeInsets? safePadding,
    double textScale = 1,
    bool dark = false,
    bool navigation = false,
    Locale locale = const Locale('ru'),
    int weekScore = 45210,
    int cityBest = 45210,
    int trafficBest = 1200,
    int signsBest = 150,
    int crossroadsBest = 150,
    bool premium = false,
    bool runsLoaded = true,
    bool pending = false,
    int runs = 3,
    DateTime? refillAt,
    VoidCallback? onCity,
    VoidCallback? onTrafficController,
    VoidCallback? onSigns,
    VoidCallback? onCrossroads,
    VoidCallback? onLeaderboard,
    VoidCallback? onRunsInfo,
    VoidCallback? onPremium,
    VoidCallback? onRefilled,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    updateAppLocale(locale);
    final key = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: safePadding,
            viewPadding: safePadding,
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            body: GamesHubView(
              weekScore: weekScore,
              cityBest: cityBest,
              trafficBest: trafficBest,
              signsBest: signsBest,
              crossroadsBest: crossroadsBest,
              premium: premium,
              runsLoaded: runsLoaded,
              hasPendingRun: pending,
              runs: runs,
              refillAt: refillAt,
              onCity: onCity ?? () {},
              onTrafficController: onTrafficController ?? () {},
              onSigns: onSigns ?? () {},
              onCrossroads: onCrossroads ?? () {},
              onLeaderboard: onLeaderboard ?? () {},
              onRunsInfo: onRunsInfo ?? () {},
              onPremium: onPremium ?? () {},
              onRefilled: onRefilled,
            ),
            bottomNavigationBar: navigation ? const _AppNavigation() : null,
          ),
        ),
      ),
    );

    // Decode the actual optimized covers before checking or capturing layout.
    await tester.runAsync(() async {
      final context = key.currentContext!;
      await Future.wait([
        for (final image in tester.widgetList<Image>(find.byType(Image)))
          precacheImage(image.image, context),
      ]);
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return key;
  }

  testWidgets('All five covers fit the available height without extra scroll', (
    tester,
  ) async {
    for (final size in [
      const Size(390, 760),
      const Size(320, 480),
      const Size(430, 932),
      const Size(768, 1024),
      const Size(1024, 768),
      const Size(844, 390),
    ]) {
      await open(tester, size: size);
      for (final key in _cardKeys) {
        final rect = tester.getRect(find.byKey(ValueKey(key)));
        expect(rect.width, greaterThan(0), reason: '$size / $key');
        expect(rect.left, greaterThanOrEqualTo(0), reason: '$size / $key');
        expect(
          rect.right,
          lessThanOrEqualTo(size.width),
          reason: '$size / $key',
        );
        expect(rect.top, greaterThanOrEqualTo(0), reason: '$size / $key');
        expect(
          rect.bottom,
          lessThanOrEqualTo(size.height),
          reason: '$size / $key',
        );
      }
      for (final scrollable in tester.stateList<ScrollableState>(
        find.byType(Scrollable),
      )) {
        expect(
          scrollable.position.maxScrollExtent,
          lessThanOrEqualTo(0.5),
          reason: 'Unnecessary scrolling at $size',
        );
      }
      expect(tester.takeException(), isNull, reason: '$size');
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Phone grid expands with height and keeps the city cover wide', (
    tester,
  ) async {
    await open(tester, size: const Size(320, 480));
    final compact = tester.getRect(
      find.byKey(const ValueKey('games-card-parking')),
    );
    await open(tester, size: const Size(320, 740));
    final parking = tester.getRect(
      find.byKey(const ValueKey('games-card-parking')),
    );
    final signs = tester.getRect(
      find.byKey(const ValueKey('games-card-signs')),
    );
    final regulator = tester.getRect(
      find.byKey(const ValueKey('games-card-regulator')),
    );
    final crossroads = tester.getRect(
      find.byKey(const ValueKey('games-card-crossroads')),
    );
    final city = tester.getRect(find.byKey(const ValueKey('games-card-city')));
    expect(parking.height, greaterThan(compact.height));
    expect(parking.top, closeTo(signs.top, 0.1));
    expect(regulator.top, closeTo(crossroads.top, 0.1));
    expect(city.left, closeTo(parking.left, 0.1));
    expect(city.right, closeTo(signs.right, 0.1));
    expect(city.top, greaterThanOrEqualTo(regulator.bottom));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Full and exhausted hubs fit above the actual app navigation', (
    tester,
  ) async {
    for (final size in [
      const Size(390, 844),
      const Size(320, 568),
      const Size(844, 390),
    ]) {
      for (final runs in [3, 0]) {
        await open(
          tester,
          size: size,
          navigation: true,
          runs: runs,
          refillAt: runs == 0
              ? DateTime.now().add(const Duration(minutes: 38))
              : null,
        );
        final navigationTop = tester.getTopLeft(find.byType(_AppNavigation)).dy;
        for (final key in _cardKeys) {
          final rect = tester.getRect(find.byKey(ValueKey(key)));
          expect(
            rect.bottom,
            lessThanOrEqualTo(navigationTop),
            reason: '$size / $runs runs / $key',
          );
        }
        for (final scrollable in tester.stateList<ScrollableState>(
          find.byType(Scrollable),
        )) {
          expect(
            scrollable.position.maxScrollExtent,
            lessThanOrEqualTo(0.5),
            reason: 'Unnecessary scrolling at $size / $runs runs',
          );
        }
        if (size.width == 320) {
          final title = tester.renderObject<RenderParagraph>(
            find.text(appL10n.gameTrafficControllerTitle),
          );
          expect(
            title.getBoxesForSelection(
              TextSelection(
                baseOffset: 0,
                extentOffset: appL10n.gameTrafficControllerTitle.length,
              ),
            ),
            hasLength(1),
            reason: 'Keep the regulator title readable as a complete word',
          );
        }
        expect(tester.takeException(), isNull, reason: '$size / $runs runs');
      }
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Full and exhausted hubs fit between device safe areas and nav', (
    tester,
  ) async {
    for (final device in [
      (
        size: const Size(320, 568),
        padding: const EdgeInsets.only(top: 24, bottom: 24),
      ),
      (
        size: const Size(390, 844),
        padding: const EdgeInsets.only(top: 44, bottom: 34),
      ),
    ]) {
      for (final runs in [3, 0]) {
        await open(
          tester,
          size: device.size,
          safePadding: device.padding,
          navigation: true,
          runs: runs,
          refillAt: runs == 0
              ? DateTime.now().add(const Duration(minutes: 38))
              : null,
        );
        final navigationTop = tester.getTopLeft(find.byType(_AppNavigation)).dy;
        for (final key in _cardKeys) {
          final rect = tester.getRect(find.byKey(ValueKey(key)));
          expect(
            rect.top,
            greaterThanOrEqualTo(device.padding.top),
            reason: '${device.size} / $runs runs / $key',
          );
          expect(
            rect.bottom,
            lessThanOrEqualTo(navigationTop),
            reason: '${device.size} / $runs runs / $key',
          );
        }
        for (final scrollable in tester.stateList<ScrollableState>(
          find.byType(Scrollable),
        )) {
          expect(
            scrollable.position.maxScrollExtent,
            lessThanOrEqualTo(0.5),
            reason: 'Unnecessary scrolling at ${device.size} / $runs runs',
          );
        }
        expect(
          tester.takeException(),
          isNull,
          reason: '${device.size} / $runs runs',
        );
      }
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Accessible text gets a readable single column and useful scroll',
    (tester) async {
      for (final scale in [1.6, 2.0]) {
        await open(
          tester,
          size: const Size(320, 740),
          navigation: true,
          textScale: scale,
          weekScore: 123456789,
          trafficBest: 123456789,
        );
        final parking = tester.getRect(
          find.byKey(const ValueKey('games-card-parking')),
        );
        final signs = tester.getRect(
          find.byKey(const ValueKey('games-card-signs')),
        );
        expect(signs.left, closeTo(parking.left, 0.1));
        expect(signs.top, greaterThanOrEqualTo(parking.bottom));
        expect(
          tester
              .stateList<ScrollableState>(find.byType(Scrollable))
              .any((scrollable) => scrollable.position.maxScrollExtent > 0),
          isTrue,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('games-card-city')),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'Text scale $scale');
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Waiting state stays readable at intermediate text sizes', (
    tester,
  ) async {
    for (final scale in [1.2, 1.3]) {
      await open(
        tester,
        navigation: true,
        textScale: scale,
        runs: 0,
        refillAt: DateTime.now().add(const Duration(minutes: 38)),
      );
      final card = tester.getRect(
        find.byKey(const ValueKey('games-card-city')),
      );
      for (final finder in [
        find.text(appL10n.gameCityTitle),
        find.textContaining(appL10n.gamesRefillIn('')),
        find.text(appL10n.gamesUnlimitedAction),
      ]) {
        final label = tester.getRect(finder);
        expect(card.contains(label.topLeft), isTrue);
        expect(card.contains(label.bottomRight), isTrue);
      }
      expect(tester.takeException(), isNull, reason: 'Text scale $scale');
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('A new player sees play prompts rather than zero records', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(
      tester,
      weekScore: 0,
      cityBest: 0,
      trafficBest: 0,
      signsBest: 0,
      crossroadsBest: 0,
    );
    expect(find.text(appL10n.gamesPlay), findsWidgets);
    expect(find.bySemanticsLabel(appL10n.gamesRecordScore('0')), findsNothing);
    expect(find.text(appL10n.gameSoonBadge), findsOneWidget);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('An exhausted new player hears the waiting state for the city', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await open(
      tester,
      runs: 0,
      weekScore: 0,
      cityBest: 0,
      trafficBest: 0,
      signsBest: 0,
      crossroadsBest: 0,
      refillAt: DateTime.now().add(const Duration(minutes: 38)),
    );
    final card = tester.widget<Semantics>(
      find.byKey(const ValueKey('games-card-city')),
    );
    expect(card.properties.label, contains(appL10n.gameFuelEmptyTitle));
    expect(card.properties.label, isNot(contains(appL10n.gamesPlay)));
    expect(find.text(appL10n.gamesRunsFraction(0, 3)), findsNothing);
    expect(find.textContaining(appL10n.gamesRefillIn('')), findsOneWidget);
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Premium removes run limits and the unlimited upsell', (
    tester,
  ) async {
    await open(
      tester,
      premium: true,
      runs: 0,
      refillAt: DateTime.now().add(const Duration(minutes: 38)),
    );
    expect(find.text(appL10n.gamesRunsFraction(0, 3)), findsNothing);
    expect(find.text(appL10n.gamesUnlimitedAction), findsNothing);
    expect(find.textContaining('38:'), findsNothing);
    expect(find.byKey(const ValueKey('games-runs-info')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'An exhausted player keeps the other games and gets a clear refill',
    (tester) async {
      var city = 0;
      var premium = 0;
      var signs = 0;
      await open(
        tester,
        runs: 0,
        refillAt: DateTime.now().add(const Duration(minutes: 38, seconds: 42)),
        onCity: () => city++,
        onPremium: () => premium++,
        onSigns: () => signs++,
      );
      expect(find.text(appL10n.gamesRunsFraction(0, 3)), findsNothing);
      expect(find.textContaining(appL10n.gamesRefillIn('')), findsOneWidget);
      expect(find.text(appL10n.gamesUnlimitedAction), findsOneWidget);
      await tester.tap(find.text(appL10n.gamesUnlimitedAction));
      expect(premium, 1);
      await tester.tap(find.byKey(const ValueKey('games-card-signs')));
      expect(signs, 1);
      expect(city, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('A saved drive remains resumable with no new free runs', (
    tester,
  ) async {
    var city = 0;
    await open(
      tester,
      runs: 0,
      pending: true,
      refillAt: DateTime.now().add(const Duration(minutes: 38)),
      onCity: () => city++,
    );
    expect(find.text(appL10n.gamesResumeRide), findsOneWidget);
    expect(find.text(appL10n.gamesRunsFraction(0, 3)), findsNothing);
    expect(find.textContaining(appL10n.gamesRefillIn('')), findsOneWidget);
    await tester.tapAt(tester.getCenter(find.text(appL10n.gamesResumeRide)));
    expect(city, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Game covers and the weekly score invoke their own action', (
    tester,
  ) async {
    final called = <String>[];
    await open(
      tester,
      onCity: () => called.add('city'),
      onTrafficController: () => called.add('regulator'),
      onSigns: () => called.add('signs'),
      onCrossroads: () => called.add('crossroads'),
      onLeaderboard: () => called.add('leaderboard'),
    );
    for (final key in _cardKeys) {
      await tester.tapAt(tester.getCenter(find.byKey(ValueKey(key))));
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('games-leaderboard')));
    expect(called, ['signs', 'regulator', 'crossroads', 'city', 'leaderboard']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Run information has its own target inside the city card', (
    tester,
  ) async {
    var city = 0;
    var info = 0;
    await open(tester, onCity: () => city++, onRunsInfo: () => info++);
    expect(find.text(appL10n.gamesRunsFraction(3, 3)), findsOneWidget);
    final target = find.byKey(const ValueKey('games-runs-info'));
    expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
    await tester.tap(target);
    expect(info, 1);
    expect(city, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('An elapsed refill deadline refreshes the run supply once', (
    tester,
  ) async {
    var refills = 0;
    await open(
      tester,
      runs: 0,
      refillAt: DateTime.now().subtract(const Duration(seconds: 1)),
      onRefilled: () => refills++,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(refills, 1);
    await tester.pump(const Duration(seconds: 5));
    expect(refills, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  final exportScreenshots =
      Platform.environment['GAMES_HUB_SCREENSHOTS'] == '1' ||
      const bool.fromEnvironment('GAMES_HUB_SCREENSHOTS');
  testWidgets('Export actual games hub states with app navigation', (
    tester,
  ) async {
    final out = Directory('output/games-hub');
    await tester.runAsync(() => out.create(recursive: true));

    Future<void> capture(
      String name, {
      int runs = 3,
      bool premium = false,
      bool pending = false,
      bool zero = false,
      bool dark = false,
      bool runsLoaded = true,
      double textScale = 1,
      Size size = const Size(390, 844),
      Locale locale = const Locale('ru'),
      bool bottom = false,
    }) async {
      final key = await open(
        tester,
        navigation: true,
        size: size,
        textScale: textScale,
        locale: locale,
        runs: runs,
        premium: premium,
        pending: pending,
        dark: dark,
        runsLoaded: runsLoaded,
        weekScore: zero ? 0 : 45210,
        cityBest: zero ? 0 : 45210,
        trafficBest: zero ? 0 : 1200,
        signsBest: zero ? 0 : 150,
        crossroadsBest: zero ? 0 : 150,
        refillAt: runs < 3
            ? DateTime.now().add(const Duration(minutes: 38, seconds: 42))
            : null,
      );
      if (bottom) {
        await tester.ensureVisible(
          find.byKey(const ValueKey('games-card-city')),
        );
        await tester.pump();
      }
      expect(tester.takeException(), isNull, reason: name);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${out.path}/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
    }

    await capture('01-full-runs');
    await capture('02-two-runs', runs: 2);
    await capture('03-last-run', runs: 1);
    await capture('04-no-runs', runs: 0);
    await capture('05-saved-drive', runs: 0, pending: true);
    await capture('06-premium', runs: 0, premium: true);
    await capture('07-new-player', zero: true);
    await capture('08-dark', dark: true, runs: 1);
    await capture('09-compact', size: const Size(320, 568), runs: 0);
    await capture('10-tablet', size: const Size(768, 1024));
    await capture('11-landscape', size: const Size(844, 390));
    await capture('12-large-text', textScale: 2);
    await capture('13-large-text-city', textScale: 2, bottom: true, runs: 0);
    await capture('14-english', locale: const Locale('en'), runs: 1);
    await capture('15-kazakh', locale: const Locale('kk'), runs: 0);
    await capture('16-loading-runs', runsLoaded: false);
    await capture('17-new-player-no-runs', zero: true, runs: 0);
    await capture('18-compact-full', size: const Size(320, 568));
  }, skip: !exportScreenshots);
}

/// Mirrors HomeScreen's actual navigation styles, icons and localized labels.
class _AppNavigation extends StatelessWidget {
  const _AppNavigation();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(height: 1, color: colors.divider),
        NavigationBar(
          selectedIndex: 1,
          onDestinationSelected: (_) {},
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.menu_book_outlined),
              selectedIcon: const Icon(Icons.menu_book),
              label: appL10n.training,
            ),
            NavigationDestination(
              icon: const Icon(Icons.sports_esports_outlined),
              selectedIcon: const Icon(Icons.sports_esports_rounded),
              label: appL10n.navGames,
            ),
            NavigationDestination(
              icon: const Icon(Icons.style_outlined),
              selectedIcon: const Icon(Icons.style_rounded),
              label: appL10n.video,
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline_rounded),
              selectedIcon: const Icon(Icons.person_rounded),
              label: appL10n.profile,
            ),
          ],
        ),
      ],
    );
  }
}
