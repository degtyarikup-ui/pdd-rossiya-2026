import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdd_app/core/layout/app_content_frame.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/services/notification_inbox_service.dart';
import 'package:pdd_app/data/services/remote_notifications_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/home/desktop_study_dashboard.dart';
import 'package:pdd_app/presentation/screens/notifications/notifications_screen.dart';
import 'package:pdd_app/presentation/widgets/app_navigation_shell.dart';
import 'package:pdd_app/presentation/widgets/notifications_bell_button.dart';
import 'package:pdd_app/presentation/widgets/premium_benefits_screen.dart';

const _stats = {
  'correctAnswers': 130,
  'answeredQuestions': 244,
  'wrongQuestions': 114,
  'passedTickets': 1,
  'totalQuestions': 800,
  'totalTickets': 40,
};
const _newsId = 'c069e042-5b7b-40a0-b15e-b80c4444ce1d';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initAppDateFormatting();
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
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => updateAppLocale(const Locale('ru')));

  void viewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app(
    Widget child, {
    String lang = 'ru',
    double scale = 1,
    bool dark = false,
  }) {
    updateAppLocale(Locale(lang));
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      locale: Locale(lang),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: child,
    );
  }

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    if (!const bool.fromEnvironment('PDD_CAPTURE_DESKTOP_V2')) return;
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('output/desktop-v2/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<NotificationInboxService> inbox(
    WidgetTester tester, {
    bool empty = false,
  }) async {
    final service = NotificationInboxService.forTesting(
      premium: () => false,
      premiumUntil: () => null,
      userId: () => null,
      sbpAvailable: () async => false,
      now: () => DateTime(2026, 10, 28),
    );
    await tester.runAsync(() async {
      await service.init();
      await service.refresh();
      await Future<void>.delayed(Duration.zero);
    });
    if (!empty) {
      service.setNews([
        AppNotice(
          id: _newsId,
          title: 'Новости приложения',
          body: 'Добавили новые разборы и обновили приложение. ' * 12,
          kind: 'news',
          createdAt: DateTime(2026, 10, 27),
          expiresAt: DateTime(2027),
        ),
        AppNotice(
          id: 'd169e042-5b7b-40a0-b15e-b80c4444ce1d',
          title: 'Новые возможности',
          body: 'Теперь удобнее заниматься на большом экране.',
          kind: 'news',
          createdAt: DateTime(2026, 10, 26),
          expiresAt: DateTime(2027),
        ),
      ], const {});
    }
    return service;
  }

  for (final lang in ['ru', 'en', 'kk']) {
    for (final size in [const Size(1100, 768), const Size(1440, 900)]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'desktop dashboard $lang $size text $scale keeps every action reachable',
          (tester) async {
            viewport(tester, size);
            final service = await inbox(tester);
            final key = GlobalKey();
            var exams = 0, tickets = 0, marathon = 0;
            await tester.pumpWidget(
              app(
                RepaintBoundary(
                  key: key,
                  child: AppNavigationShell(
                    desktopEnabled: true,
                    selectedIndex: 0,
                    onSelected: (_) {},
                    items: [
                      (
                        icon: Icons.menu_book_outlined,
                        selectedIcon: Icons.menu_book,
                        label: appL10n.training,
                      ),
                    ],
                    desktopFooterBuilder: (extended) => NotificationsBellButton(
                      service: service,
                      showLabel: extended,
                    ),
                    child: AppContentFrame(
                      maxWidth: AppContentFrame.desktopContentWidth,
                      child: DesktopStudyDashboard(
                        progress: const DesktopProgressCard(stats: _stats),
                        category: 'A/B',
                        onExam: () => exams++,
                        onTopics: () {},
                        onTickets: () => tickets++,
                        onMistakes: () {},
                        onFavorites: () {},
                        onMarathon: () => marathon++,
                        onRate: () {},
                      ),
                    ),
                  ),
                ),
                lang: lang,
                scale: scale,
                dark: scale == 2 || lang == 'ru',
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            if (lang == 'ru' && scale == 1 && size.width == 1440) {
              await capture(tester, key, 'dashboard-dark');
            }
            final exam = find.byKey(const ValueKey('desktop-start-exam'));
            await tester.ensureVisible(exam);
            await tester.pumpAndSettle();
            await tester.tap(exam);
            final ticket = find.text(appL10n.tickets);
            await tester.ensureVisible(ticket);
            await tester.pumpAndSettle();
            await tester.tap(ticket);
            final run = find.text(appL10n.marathon);
            await tester.ensureVisible(run);
            await tester.pumpAndSettle();
            await tester.tap(run);
            expect([exams, tickets, marathon], [1, 1, 1]);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            await tester.runAsync(() async {
              await service.refresh();
              await Future<void>.delayed(Duration.zero);
            });
            service.dispose();
          },
        );
      }
    }
  }

  for (final lang in ['ru', 'en', 'kk']) {
    for (final config in [
      (size: const Size(1440, 900), scale: 1.0),
      (size: const Size(1024, 768), scale: 1.0),
      (size: const Size(390, 844), scale: 1.0),
      (size: const Size(568, 320), scale: 2.0),
      (size: const Size(768, 1024), scale: 2.0),
    ]) {
      testWidgets(
        'inbox $lang ${config.size} text ${config.scale}: read state and contents survive resize',
        (tester) async {
          viewport(tester, config.size);
          final service = await inbox(tester);
          final key = GlobalKey();
          await tester.pumpWidget(
            app(
              RepaintBoundary(
                key: key,
                child: NotificationsScreen(service: service),
              ),
              lang: lang,
              scale: config.scale,
              dark: lang == 'ru',
            ),
          );
          await tester.pumpAndSettle();
          expect(service.hasUnread, isFalse);
          expect(tester.takeException(), isNull);
          if (config.scale == 1 && config.size.width >= 900) {
            final preview = find.byKey(
              const ValueKey(
                'inbox-preview-news_d169e042-5b7b-40a0-b15e-b80c4444ce1d',
              ),
            );
            await tester.tap(preview);
            await tester.pumpAndSettle();
            final detailKey = const PageStorageKey(
              'inbox-detail-news_d169e042-5b7b-40a0-b15e-b80c4444ce1d',
            );
            expect(find.byKey(detailKey), findsOneWidget);
            if (lang == 'ru' && config.size.width == 1440) {
              await capture(tester, key, 'inbox-dark');
            }
            tester.view.physicalSize = const Size(390, 844);
            await tester.pumpAndSettle();
            tester.view.physicalSize = config.size;
            await tester.pumpAndSettle();
            expect(find.byKey(detailKey), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(() async {
            await service.refresh();
            await Future<void>.delayed(Duration.zero);
          });
          service.dispose();
        },
      );
    }
  }

  testWidgets(
    'desktop inbox selects a message without opening its action, then Escape returns',
    (tester) async {
      viewport(tester, const Size(1440, 900));
      final service = NotificationInboxService.forTesting(
        premium: () => false,
        premiumUntil: () => null,
        userId: () => 'layout-test',
        sbpAvailable: () async => true,
      );
      await tester.runAsync(() async {
        await service.init();
        await service.refresh();
        await Future<void>.delayed(Duration.zero);
      });
      await tester.runAsync(service.refresh);
      await tester.pumpWidget(app(NotificationsScreen(service: service)));
      await tester.pumpAndSettle();
      expect(find.byType(PremiumBenefitsScreen), findsNothing);
      await tester.tap(
        find.widgetWithText(FilledButton, appL10n.inboxSbpAction),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PremiumBenefitsScreen), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(PremiumBenefitsScreen), findsNothing);
      expect(find.byType(NotificationsScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await service.refresh();
        await Future<void>.delayed(Duration.zero);
      });
      service.dispose();
    },
  );

  testWidgets('empty inbox fits a short window with large text', (
    tester,
  ) async {
    viewport(tester, const Size(568, 320));
    final service = await inbox(tester, empty: true);
    await tester.pumpWidget(
      app(NotificationsScreen(service: service), scale: 2),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(appL10n.inboxEmpty), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await service.refresh();
      await Future<void>.delayed(Duration.zero);
    });
    service.dispose();
  });
}
