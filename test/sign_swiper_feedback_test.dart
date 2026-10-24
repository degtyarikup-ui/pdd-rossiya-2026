import 'package:pdd_app/presentation/screens/games/widgets/mini_game_hud.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/sign_swiper_model.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/games/sign_swiper/widgets/swipe_card_view.dart';

const question = SignCardQuestion(
  id: 'feedback',
  sign: SignItem(
    number: '3.1',
    title: '',
    image: '9f77764c15a21428b8e6e7f5c75936e2.svg',
    category: '',
    description: '',
  ),
  prompt: 'Разрешён ли въезд под этот знак?',
  isCorrect: false,
  explanation: '',
  type: SignQuestionType.actionPermission,
);

void main() {
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
  setUp(() => HapticFeedbackHelper.setEnabled(false));
  tearDown(() {
    HapticFeedbackHelper.setEnabled(true);
    updateAppLocale(const Locale('ru'));
  });

  Future<void> open(
    WidgetTester tester,
    SwipeCardController controller, {
    String language = 'ru',
    bool dark = false,
    bool reduced = false,
    double scale = 1,
    Size size = const Size(390, 740),
    ValueChanged<bool>? onAnswered,
    ValueChanged<bool>? onSwiped,
    SignCardQuestion card = question,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    updateAppLocale(Locale(language));
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduced,
          ),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: size.width - 40,
                height: size.height - 180,
                child: RepaintBoundary(
                  key: const ValueKey('preview'),
                  child: SwipeCardView(
                    card: card,
                    controller: controller,
                    onAnswered: onAnswered,
                    onSwiped: onSwiped ?? (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      // SVG decoding uses the asset bundle and an isolate outside fake time.
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('PDD_CAPTURE_SWIPER')) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('preview')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('output/sign-swiper').create(recursive: true);
      await File(
        'output/sign-swiper/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'Wrong answer stays readable, locks repeat taps, then departs once',
    (tester) async {
      final controller = SwipeCardController();
      final answered = <bool>[], swiped = <bool>[];
      await open(
        tester,
        controller,
        onAnswered: answered.add,
        onSwiped: swiped.add,
      );
      await capture(tester, 'card');
      controller.swipeRight();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      await tester.pump(const Duration(milliseconds: 180));
      expect(answered, [true]);
      expect(swiped, isEmpty);
      expect(find.byType(GameLifeLossBadge), findsOneWidget);
      expect(
        find.text(appL10n.signSwiperCorrectAnswer(question.leftActionLabel)),
        findsOneWidget,
      );
      await capture(tester, 'incorrect');
      controller.swipeLeft();
      await tester.pump(const Duration(milliseconds: 600));
      expect(answered, [true]);
      expect(swiped, isEmpty);
      await tester.pumpAndSettle();
      expect(swiped, [true]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Cancelled drag does not answer; correct NO is green feedback', (
    tester,
  ) async {
    final controller = SwipeCardController();
    final answered = <bool>[];
    await open(tester, controller, onAnswered: answered.add);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SwipeCardView)),
    );
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(answered, isEmpty);
    controller.swipeLeft();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    expect(find.text(appL10n.gameCorrect), findsOneWidget);
    expect(find.byType(GameLifeLossBadge), findsNothing);
    await capture(tester, 'correct');
    await tester.pumpAndSettle();
  });

  for (final language in ['ru', 'en', 'kk']) {
    for (final dark in [false, true]) {
      testWidgets(
        'Feedback visible with large text and reduced motion ($language, dark=$dark)',
        (tester) async {
          final controller = SwipeCardController();
          await open(
            tester,
            controller,
            language: language,
            dark: dark,
            reduced: true,
            scale: 1.6,
            size: const Size(320, 568),
          );
          controller.swipeRight();
          await tester.pump();
          await tester.pump();
          final feedback = find.byKey(const ValueKey('sign-answer-feedback'));
          expect(feedback, findsOneWidget);
          final rect = tester.getRect(feedback);
          final cardRect = tester.getRect(find.byType(SwipeCardView));
          expect(rect.top, greaterThanOrEqualTo(cardRect.top));
          expect(rect.bottom, lessThanOrEqualTo(cardRect.bottom));
          expect(tester.takeException(), isNull);
          await capture(tester, 'compact-$language-${dark ? 'dark' : 'light'}');
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 2));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  test('Incorrect haptic respects disabling between its two pulses', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            calls.add(call.arguments as String);
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    HapticFeedbackHelper.setEnabled(true);
    HapticFeedbackHelper.answerIncorrect();
    await Future<void>.delayed(const Duration(milliseconds: 130));
    expect(calls, [
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.lightImpact',
    ]);
    calls.clear();
    HapticFeedbackHelper.answerIncorrect();
    HapticFeedbackHelper.setEnabled(false);
    await Future<void>.delayed(const Duration(milliseconds: 130));
    expect(calls, ['HapticFeedbackType.mediumImpact']);
  });
}
