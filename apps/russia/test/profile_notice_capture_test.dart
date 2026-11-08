import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/models/achievement.dart';
import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/remote_notifications_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/profile/profile_screen.dart';
import 'package:pdd_app/presentation/widgets/app_navigation_shell.dart';
import 'package:pdd_app/presentation/widgets/premium_banner_card.dart';
import 'package:pdd_app/presentation/widgets/profile_notice_banner.dart';
import 'package:pdd_app/presentation/widgets/streak_widgets.dart';

// Opt-in artifact capture of production widgets, without any server writes.
const _capture = bool.fromEnvironment('PROFILE_BANNER_CAPTURE');
const _output = String.fromEnvironment(
  'PROFILE_BANNER_CAPTURE_DIR',
  defaultValue: 'output/profile-banners',
);
const _captureKey = ValueKey('profile-notice-screen-capture');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture profile placements with natural height and real assets', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    updateAppLocale(const Locale('ru'));
    await initAppDateFormatting();
    final fonts = FontLoader('Onest');
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
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();

    final bytes = <String, Uint8List>{};
    for (final name in ['traffic_controller', 'city_cover']) {
      final data = await rootBundle.load('assets/images/games/$name.webp');
      bytes['/$name.webp'] = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
    }
    bytes['/portrait.png'] = (await tester.runAsync(_portraitFixture))!;
    bytes['/low.png'] = (await tester.runAsync(_lowFixture))!;
    debugNetworkImageHttpClientProvider = () => _CaptureClient(bytes);
    final service = RemoteNotificationsService.instance;
    final previous = service.profileBanners.value;
    addTearDown(() {
      service.profileBanners.value = previous;
      debugNetworkImageHttpClientProvider = null;
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });

    AppNotice notice({
      String title = '',
      String body = '',
      String image = '',
      int? width,
      int? height,
      String button = '',
      NoticeAction action = NoticeAction.none,
    }) => AppNotice(
      id: 'a069e042-5b7b-40a0-b15e-b80c4444ce1d',
      kind: 'profile',
      title: title,
      body: body,
      imageUrl: image.isEmpty ? '' : 'https://profile-capture.test/$image',
      imageWidth: width,
      imageHeight: height,
      button: button.isNotEmpty,
      buttonText: button,
      action: action,
      layout: title.isEmpty && body.isEmpty && button.isEmpty
          ? 'image'
          : 'standard',
      expiresAt: DateTime(2099),
    );

    final full = notice(
      image: 'city_cover.webp',
      width: 1200,
      height: 675,
      title: 'Правила оживают в городе',
      body:
          'Попробуйте себя за рулём: перекрёстки, знаки и дорожные ситуации в одной игре.',
      button: 'В живой город',
      action: NoticeAction.game,
    );
    final cases = <({String name, AppNotice? notice, bool dark})>[
      (
        name: '01-text',
        notice: notice(
          body:
              'Пять минут практики сегодня — ещё один шаг к уверенности за рулём.',
        ),
        dark: false,
      ),
      (
        name: '02-button',
        notice: notice(
          button: 'Продолжить подготовку',
          action: NoticeAction.tickets,
        ),
        dark: false,
      ),
      (
        name: '03-image',
        notice: notice(
          image: 'traffic_controller.webp',
          width: 1008,
          height: 440,
          action: NoticeAction.game,
        ),
        dark: false,
      ),
      (name: '04-complete', notice: full, dark: false),
      (
        name: '05-tall',
        notice: notice(
          image: 'portrait.png',
          width: 720,
          height: 1280,
          title: 'Ваш следующий шаг',
          body:
              'Закрепите знания в тренировке. Серия занятий и достижения остаются ниже — просто прокрутите экран.',
          button: 'Начать тренировку',
          action: NoticeAction.tickets,
        ),
        dark: false,
      ),
      (name: '06-dark', notice: full, dark: true),
      (name: '07-empty', notice: null, dark: false),
      (
        name: '08-low-image',
        notice: notice(image: 'low.png', width: 1000, height: 180),
        dark: false,
      ),
    ];
    for (final item in cases) {
      await tester.pumpWidget(const SizedBox.shrink());
      service.profileBanners.value = item.notice == null ? [] : [item.notice!];
      await tester.pumpWidget(_screen(dark: item.dark));
      await tester.pump();
      await tester.runAsync(() async {
        final context = tester.element(find.byType(ProfileScreen));
        final assets = <String>[
          'assets/images/default_avatar.webp',
          'assets/images/premium/car.png',
          'assets/images/premium/rays_lime.png',
          'assets/images/premium/rays_blue.png',
          for (final achievement in _achievements)
            'assets/images/achievements/${achievement.id.name}_${achievement.level == 0 ? 1 : achievement.level}.png',
        ];
        for (final path in assets) {
          await precacheImage(AssetImage(path), context);
        }
        if (item.notice?.imageUrl.isNotEmpty ?? false) {
          await precacheImage(NetworkImage(item.notice!.imageUrl), context);
        }
      });
      await tester.pump(const Duration(milliseconds: 900));
      expect(tester.takeException(), isNull, reason: item.name);
      final premium = tester.getRect(find.byType(PremiumBannerCard));
      if (item.notice != null) {
        final banner = tester.getRect(find.byType(ProfileNoticeBanner));
        expect(
          banner.top,
          greaterThanOrEqualTo(premium.bottom),
          reason: item.name,
        );
        if (find.byType(StreakCard).evaluate().isNotEmpty) {
          expect(
            tester.getTopLeft(find.byType(StreakCard)).dy,
            greaterThan(banner.bottom),
            reason: item.name,
          );
        }
      } else {
        expect(find.byType(ProfileNoticeBanner), findsNothing);
        expect(
          tester.getTopLeft(find.byType(StreakCard)).dy,
          greaterThan(premium.bottom),
        );
      }
      if (item.name == '08-low-image') {
        final image = find.descendant(
          of: find.byType(ProfileNoticeBanner),
          matching: find.byType(RawImage),
        );
        expect(tester.getSize(image).height, closeTo(63, .01));
      }
      await _save(tester, item.name);
      if (item.name == '05-tall') {
        final list = find.descendant(
          of: find.byType(ProfileScreen),
          matching: find.byType(ListView),
        );
        await tester.drag(list, const Offset(0, -660));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(StreakCard), findsOneWidget);
        final banner = tester.getRect(find.byType(ProfileNoticeBanner));
        final streak = tester.getRect(find.byType(StreakCard));
        expect(streak.top, greaterThan(banner.bottom));
        expect(
          streak.top,
          lessThan(800),
          reason: 'lower content is reachable by scrolling',
        );
        expect(tester.takeException(), isNull);
        await _save(tester, '05-tall-scrolled');
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    debugNetworkImageHttpClientProvider = null;
  }, skip: !_capture);
}

const _achievements = [
  AchievementProgress(
    id: AchievementId.streak,
    levels: [3, 7, 14, 30],
    value: 7,
  ),
  AchievementProgress(
    id: AchievementId.coverage,
    levels: [100, 300, 500, 800],
    value: 150,
  ),
  AchievementProgress(
    id: AchievementId.tickets,
    levels: [1, 10, 20, 40],
    value: 4,
  ),
  AchievementProgress(
    id: AchievementId.attempts,
    levels: [100, 500, 1000, 3000],
    value: 220,
  ),
  AchievementProgress(id: AchievementId.exams, levels: [1, 3, 5, 10], value: 0),
  AchievementProgress(
    id: AchievementId.game,
    levels: [100, 200, 300, 450],
    value: 0,
  ),
];

Widget _screen({required bool dark}) {
  final today = Streak.day(DateTime.now());
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWithValue(
        UserProfile(
          id: 'capture_user',
          name: 'Александр',
          email: 'alex@example.com',
          useDefaultAvatar: true,
          provider: AuthProviderType.google,
          createdAt: DateTime(2026, 10, 1),
        ),
      ),
      isPremiumProvider.overrideWithValue(false),
      achievementsProvider.overrideWith((ref) async => _achievements),
      streakProvider.overrideWith(
        (ref) async => Streak(
          current: 5,
          longest: 7,
          lastActiveDate: today,
          startDate: Streak.shiftDay(today, -4),
          activeDays: {for (var i = 0; i < 5; i++) Streak.shiftDay(today, -i)},
        ),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: RepaintBoundary(
        key: _captureKey,
        child: AppNavigationShell(
          selectedIndex: 3,
          onSelected: (_) {},
          items: [
            (
              icon: Icons.menu_book_outlined,
              selectedIcon: Icons.menu_book,
              label: appL10n.training,
            ),
            (
              icon: Icons.sports_esports_outlined,
              selectedIcon: Icons.sports_esports_rounded,
              label: appL10n.navGames,
            ),
            (
              icon: Icons.style_outlined,
              selectedIcon: Icons.style_rounded,
              label: appL10n.video,
            ),
            (
              icon: Icons.person_outline_rounded,
              selectedIcon: Icons.person_rounded,
              label: appL10n.profile,
            ),
          ],
          child: const ProfileScreen(),
        ),
      ),
    ),
  );
}

Future<void> _save(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_captureKey),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(_output).create(recursive: true);
    await File('$_output/$name.png').writeAsBytes(
      data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  });
}

// A separate, original narrow fixture; existing artwork is never stretched.
Future<Uint8List> _lowFixture() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xFFDFF3E8), BlendMode.src);
  final text = TextPainter(
    text: const TextSpan(
      text: 'Каждый день — ближе к правам',
      style: TextStyle(
        fontFamily: 'Onest',
        fontSize: 40,
        fontWeight: FontWeight.w600,
        color: Color(0xFF175D3C),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 810);
  text.paint(canvas, Offset(46, (180 - text.height) / 2));
  text.dispose();
  final picture = recorder.endRecording();
  final image = await picture.toImage(1000, 180);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

// Original procedural fixture, intentionally portrait to exercise long scrolling.
Future<Uint8List> _portraitFixture() async {
  const width = 720, height = 1280;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 720, 1280),
    Paint()
      ..shader = ui.Gradient.linear(Offset.zero, const Offset(720, 1280), [
        const Color(0xFF075BE6),
        const Color(0xFF092A78),
      ]),
  );
  final road = Path()
    ..moveTo(0, 1180)
    ..cubicTo(690, 1240, 680, 850, 400, 815)
    ..cubicTo(100, 760, 80, 510, 430, 465);
  canvas.drawPath(
    road,
    Paint()
      ..color = const Color(0xFF528CFA)
      ..strokeWidth = 106
      ..style = PaintingStyle.stroke,
  );
  canvas.drawPath(
    road,
    Paint()
      ..color = const Color(0xFFD2E3FF)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke,
  );
  canvas.drawCircle(
    const Offset(430, 465),
    24,
    Paint()..color = const Color(0xFFD8FF72),
  );
  void label(
    String text,
    double y,
    double size,
    FontWeight weight,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Onest',
          fontSize: size,
          fontWeight: weight,
          height: 1.12,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 580);
    painter.paint(canvas, Offset(56, y));
    painter.dispose();
  }

  label(
    'ПРАКТИКА КАЖДЫЙ ДЕНЬ',
    62,
    22,
    FontWeight.w600,
    const Color(0xFFD8FF72),
  );
  label(
    'Уверенность\nначинается\nс одного шага',
    119,
    61,
    FontWeight.w700,
    Colors.white,
  );
  label(
    'Учитесь в своём темпе.\nМы рядом на всём пути.',
    1080,
    28,
    FontWeight.w500,
    Colors.white,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

class _CaptureClient extends Fake implements HttpClient {
  _CaptureClient(this.images);
  final Map<String, Uint8List> images;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _CaptureRequest(images[url.path]!);
}

class _CaptureRequest extends Fake implements HttpClientRequest {
  _CaptureRequest(this.bytes);
  final Uint8List bytes;
  @override
  Future<HttpClientResponse> close() async => _CaptureResponse(bytes);
}

class _CaptureResponse extends Fake implements HttpClientResponse {
  _CaptureResponse(this.bytes);
  final Uint8List bytes;
  @override
  int get statusCode => HttpStatus.ok;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}
