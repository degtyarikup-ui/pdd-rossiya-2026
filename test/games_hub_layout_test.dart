import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/games/games_hub_view.dart';

const _cardKeys = [
  'games-card-signs',
  'games-card-regulator',
  'games-card-crossroads',
  'games-card-road_signs',
  'games-card-violator',
  'games-card-parking',
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

  ScrollableState catalogueScroll(WidgetTester tester) => tester.state(
    find.descendant(
      of: find.byKey(const ValueKey('games-scroll')),
      matching: find.byType(Scrollable),
    ),
  );

  void expectCityVisible(WidgetTester tester, Size size, {double top = 0}) {
    final city = tester.getRect(find.byKey(const ValueKey('games-card-city')));
    final navigation = find.byType(_AppNavigation);
    final bottom = navigation.evaluate().isEmpty
        ? size.height
        : tester.getTopLeft(navigation).dy;
    expect(city.left, greaterThanOrEqualTo(0));
    expect(city.right, lessThanOrEqualTo(size.width));
    expect(city.top, greaterThanOrEqualTo(top));
    expect(city.bottom, lessThanOrEqualTo(bottom));
  }

  testWidgets('All seven covers fit regular screens without extra scroll', (
    tester,
  ) async {
    for (final size in [
      const Size(390, 760),
      const Size(430, 932),
      const Size(768, 1024),
      const Size(1024, 768),
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
      expect(
        catalogueScroll(tester).position.maxScrollExtent,
        lessThanOrEqualTo(0.5),
        reason: 'Unnecessary scrolling at $size',
      );
      expect(tester.takeException(), isNull, reason: '$size');
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Available games precede upcoming games above the pinned city', (
    tester,
  ) async {
    await open(tester, size: const Size(320, 480));
    expect(catalogueScroll(tester).position.maxScrollExtent, greaterThan(0));
    expectCityVisible(tester, const Size(320, 480));
    await open(tester, size: const Size(390, 760));
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
    final roadSigns = tester.getRect(
      find.byKey(const ValueKey('games-card-road_signs')),
    );
    final violator = tester.getRect(
      find.byKey(const ValueKey('games-card-violator')),
    );
    final city = tester.getRect(find.byKey(const ValueKey('games-card-city')));
    expect(signs.top, closeTo(regulator.top, 0.1));
    expect(crossroads.top, greaterThanOrEqualTo(signs.bottom));
    expect(roadSigns.top, closeTo(crossroads.top, 0.1));
    expect(violator.top, greaterThanOrEqualTo(crossroads.bottom));
    expect(parking.top, closeTo(violator.top, 0.1));
    expect(city.left, closeTo(signs.left, 0.1));
    expect(city.right, closeTo(regulator.right, 0.1));
    expect(city.top, greaterThanOrEqualTo(parking.bottom));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'The city stays visible above navigation while mini games scroll',
    (tester) async {
      for (final size in [
        const Size(390, 844),
        const Size(320, 480),
        const Size(320, 568),
        const Size(844, 390),
        const Size(568, 320),
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
          expectCityVisible(tester, size);
          final cityBefore = tester.getRect(
            find.byKey(const ValueKey('games-card-city')),
          );
          final scroll = catalogueScroll(tester).position;
          if (size.width == 320) expect(scroll.maxScrollExtent, greaterThan(0));
          scroll.jumpTo(scroll.maxScrollExtent);
          await tester.pump();
          expect(
            tester.getRect(find.byKey(const ValueKey('games-card-city'))),
            cityBefore,
            reason: '$size / $runs runs',
          );
          expectCityVisible(tester, size);
          if (size.width > size.height) {
            final catalogue = tester.getRect(
              find.byKey(const ValueKey('games-scroll')),
            );
            expect(cityBefore.left, greaterThanOrEqualTo(catalogue.right));
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
    },
  );

  testWidgets('The pinned city fits between device safe areas and navigation', (
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
        expectCityVisible(tester, device.size, top: device.padding.top);
        final cityBefore = tester.getRect(
          find.byKey(const ValueKey('games-card-city')),
        );
        final scroll = catalogueScroll(tester).position;
        scroll.jumpTo(scroll.maxScrollExtent);
        await tester.pump();
        expect(
          tester.getRect(find.byKey(const ValueKey('games-card-city'))),
          cityBefore,
        );
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
    'Accessible text scrolls a single mini column and keeps city fixed',
    (tester) async {
      for (final device in [
        (size: const Size(320, 740), scale: 1.6),
        (size: const Size(320, 740), scale: 2.0),
        (size: const Size(320, 568), scale: 2.0),
      ]) {
        await open(
          tester,
          size: device.size,
          navigation: true,
          textScale: device.scale,
          weekScore: 123456789,
          trafficBest: 123456789,
        );
        final signs = tester.getRect(
          find.byKey(const ValueKey('games-card-signs')),
        );
        final regulator = tester.getRect(
          find.byKey(const ValueKey('games-card-regulator')),
        );
        expect(signs.left, closeTo(regulator.left, 0.1));
        expect(regulator.top, greaterThanOrEqualTo(signs.bottom));
        expect(
          tester
              .stateList<ScrollableState>(find.byType(Scrollable))
              .any((scrollable) => scrollable.position.maxScrollExtent > 0),
          isTrue,
        );
        expectCityVisible(tester, device.size);
        final cityBefore = tester.getRect(
          find.byKey(const ValueKey('games-card-city')),
        );
        final scroll = catalogueScroll(tester).position;
        scroll.jumpTo(scroll.maxScrollExtent);
        await tester.pump();
        expect(
          tester.getRect(find.byKey(const ValueKey('games-card-city'))),
          cityBefore,
        );
        expectCityVisible(tester, device.size);
        expect(
          tester.takeException(),
          isNull,
          reason: '${device.size} / text scale ${device.scale}',
        );
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Short landscape keeps the city action readable with large text',
    (tester) async {
      for (final device in [
        (size: const Size(568, 320), scale: 1.6),
        (size: const Size(568, 320), scale: 2.0),
        (size: const Size(640, 360), scale: 2.0),
      ]) {
        for (final runs in [3, 0]) {
          await open(
            tester,
            size: device.size,
            textScale: device.scale,
            navigation: true,
            runs: runs,
            safePadding: const EdgeInsets.only(bottom: 21),
            refillAt: runs == 0
                ? DateTime.now().add(const Duration(minutes: 38))
                : null,
          );
          expectCityVisible(tester, device.size);
          final card = tester.getRect(
            find.byKey(const ValueKey('games-card-city')),
          );
          for (final text in [
            appL10n.gameCityTitle,
            runs == 0 ? appL10n.gamesUnlimitedAction : appL10n.gamesPlay,
          ]) {
            final rect = tester.getRect(find.text(text));
            expect(card.contains(rect.topLeft), isTrue);
            expect(card.contains(rect.bottomRight), isTrue);
          }
          expect(tester.takeException(), isNull, reason: '$device / $runs');
        }
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

  testWidgets(
    'Weekly rating and all-time round records have visible distinct labels',
    (tester) async {
      for (final locale in [
        const Locale('ru'),
        const Locale('en'),
        const Locale('kk'),
      ]) {
        var leaderboardOpens = 0;
        await open(
          tester,
          locale: locale,
          weekScore: 978,
          cityBest: 4387,
          trafficBest: 4050,
          signsBest: 1500,
          crossroadsBest: 702,
          onLeaderboard: () => leaderboardOpens++,
        );
        expect(find.text(appL10n.gamesWeeklyScoreLabel), findsOneWidget);
        expect(find.text('978'), findsOneWidget);
        final number = NumberFormat.decimalPattern(locale.languageCode);
        for (final score in [1500, 4050, 702, 4387]) {
          expect(
            find.text(appL10n.gamesRecordScore(number.format(score))),
            findsOneWidget,
          );
        }
        await tester.tap(find.byKey(const ValueKey('games-leaderboard')));
        expect(leaderboardOpens, 1);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

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
    expect(find.text(appL10n.gameSoonBadge), findsNWidgets(3));
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Upcoming games have localized names and no launch action', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    for (final locale in [
      const Locale('ru'),
      const Locale('en'),
      const Locale('kk'),
    ]) {
      await open(tester, locale: locale);
      for (final entry in [
        ('road_signs', appL10n.gamesRoadSignsTitle),
        ('violator', appL10n.gamesViolatorTitle),
        ('parking', appL10n.gamesParkingTitle),
      ]) {
        final finder = find.byKey(ValueKey('games-card-${entry.$1}'));
        final card = tester.widget<Semantics>(finder);
        expect(card.properties.label, '${entry.$2}, ${appL10n.gameSoonBadge}');
        expect(card.properties.enabled, isFalse);
        expect(card.properties.onTap, isNull);
        expect(find.text(entry.$2), findsOneWidget);
        expect(
          tester
              .getSemantics(finder)
              .getSemanticsData()
              .hasAction(ui.SemanticsAction.tap),
          isFalse,
        );
      }
      expect(tester.takeException(), isNull, reason: locale.languageCode);
    }
    handle.dispose();
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
    expect(card.properties.label, contains(appL10n.gamesUnlimitedAction));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('games-card-city')),
        matching: find.text(appL10n.gamesPlay),
      ),
      findsNothing,
    );
    expect(find.text(appL10n.gamesRunsFraction(0, 3)), findsNothing);
    expect(find.textContaining(appL10n.gamesRefillIn('')), findsOneWidget);
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('A saved run does not offer to continue without runs', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await open(
      tester,
      runs: 0,
      pending: true,
      refillAt: DateTime.now().add(const Duration(minutes: 59)),
    );
    final card = tester.widget<Semantics>(
      find.byKey(const ValueKey('games-card-city')),
    );
    expect(card.properties.label, contains(appL10n.gameFuelEmptyTitle));
    expect(card.properties.label, isNot(contains(appL10n.gamesResumeRide)));
    expect(find.text(appL10n.gamesResumeRide), findsNothing);
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
    expect(find.byIcon(Icons.local_gas_station_rounded), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'An exhausted player keeps the other games and gets a clear refill',
    (tester) async {
      var city = 0;
      var signs = 0;
      await open(
        tester,
        runs: 0,
        refillAt: DateTime.now().add(const Duration(minutes: 38, seconds: 42)),
        onCity: () => city++,
        onSigns: () => signs++,
      );
      expect(find.text(appL10n.gamesRunsFraction(0, 3)), findsNothing);
      expect(find.textContaining(appL10n.gamesRefillIn('')), findsOneWidget);
      expect(find.text(appL10n.gamesUnlimitedAction), findsOneWidget);
      await tester.tapAt(
        tester.getCenter(find.text(appL10n.gamesUnlimitedAction)),
      );
      expect(city, 1);
      await tester.tap(find.byKey(const ValueKey('games-card-signs')));
      expect(signs, 1);
      expect(city, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

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

  testWidgets('Every city area uses one action and no nested semantic button', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var city = 0;
    await open(
      tester,
      onCity: () => city++,
      refillAt: DateTime.now().add(const Duration(minutes: 38)),
    );
    expect(find.text(appL10n.gamesRunsFraction(3, 3)), findsOneWidget);
    final card = find.byKey(const ValueKey('games-card-city'));
    final status = find.byKey(const ValueKey('games-runs-status'));
    expect(find.byKey(const ValueKey('games-runs-info')), findsNothing);
    final node = tester.getSemantics(card);
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    expect(
      node.debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder),
      isEmpty,
    );
    for (final area in [
      find.text(appL10n.gameCityTitle),
      find.text(appL10n.gamesPlay).last,
      status,
      find.text(appL10n.gamesRunsFraction(3, 3)),
      find.textContaining(appL10n.gamesRefillIn('')),
    ]) {
      await tester.tapAt(tester.getCenter(area));
      await tester.pump();
    }
    await tester.tapAt(tester.getTopRight(card) + const Offset(-12, 12));
    expect(city, 6);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
    handle.dispose();
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
        final scroll = catalogueScroll(tester).position;
        scroll.jumpTo(scroll.maxScrollExtent);
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
    await capture(
      '13-large-text-scrolled',
      textScale: 2,
      bottom: true,
      runs: 0,
    );
    await capture('14-english', locale: const Locale('en'), runs: 1);
    await capture('15-kazakh', locale: const Locale('kk'), runs: 0);
    await capture('16-loading-runs', runsLoaded: false);
    await capture('17-new-player-no-runs', zero: true, runs: 0);
    await capture('18-compact-full', size: const Size(320, 568));
    await capture(
      '19-compact-scrolled',
      size: const Size(320, 568),
      bottom: true,
    );
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
