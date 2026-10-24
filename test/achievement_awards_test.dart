import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/presentation/widgets/streak_celebration_dialog.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/models/achievement.dart';
import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/presentation/widgets/celebration_screen.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/achievement_award_service.dart';
import 'package:pdd_app/data/services/review_prompt_service.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/exam/exam_screen.dart';
import 'package:pdd_app/presentation/screens/game/godot_game.dart';
import 'package:pdd_app/presentation/screens/training/training_result_screen.dart';
import 'package:pdd_app/presentation/screens/training/training_screen.dart';
import 'package:pdd_app/presentation/widgets/achievement_award_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SilentTts implements TtsService {
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<void> updateLanguage(String lang) async {}
  @override
  Future<void> speakQuestion({
    String? rawQuestionId,
    required String question,
    required List<String> answers,
  }) async {}
  @override
  Future<Duration?> speakOrPlayFeedItem({
    required String? rawQuestionId,
    required String question,
    required List<String> answers,
  }) async => null;
}

AchievementProgress badge(AchievementId id, int value) =>
    AchievementProgress(id: id, value: value, levels: const [3, 7, 14, 30]);

List<Map<String, dynamic>> questions() => List.generate(
  2,
  (i) => {
    'id': 'q$i',
    'question': 'Вопрос ${i + 1}',
    'ticketNumber': 1,
    'answers': [
      {'text': 'Верный ответ', 'correct': true},
      {'text': 'Неверный ответ', 'correct': false},
    ],
    'comment': '',
    'image': null,
    'topic': <String>[],
    'pddPoints': <String>[],
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SoundEffectsService.instance.setEnabled(false);
    TestWidgetsFlutterBinding
        .instance
        .platformDispatcher
        .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    SharedPreferences.setMockInitialValues({});
    updateAppLocale(const Locale('ru'));
  });
  tearDown(() {
    SoundEffectsService.instance.setEnabled(true);
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearAccessibilityFeaturesTestValue();
  });
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

  test(
    'upgrade baseline, highest new tier, persistence and no repeat after restart',
    () async {
      var current = [badge(AchievementId.streak, 3)];
      var service = AchievementAwardService(
        scope: 'ab',
        load: () async => current,
      );
      await service.prepare();
      expect(await service.pending(), isEmpty);
      current = [badge(AchievementId.streak, 30)];
      expect((await service.pending()).single.level, 4);
      await service.acknowledge(AchievementId.streak, 4);
      service = AchievementAwardService(scope: 'ab', load: () async => current);
      expect(await service.pending(), isEmpty);
      await service.acknowledge(AchievementId.streak, 1);
      expect((await service.receipts())['streak'], 4);
    },
  );

  test(
    'leaving an activity does not consume earned, unpresented awards',
    () async {
      var current = [badge(AchievementId.attempts, 0)];
      final service = AchievementAwardService(
        scope: 'ab',
        load: () async => current,
      );
      await service.prepare();
      current = [badge(AchievementId.attempts, 7)];
      final afterRestart = AchievementAwardService(
        scope: 'ab',
        load: () async => current,
      );
      expect((await afterRestart.pending()).single.level, 2);
      expect((await service.pending()).single.level, 2);
    },
  );

  testWidgets(
    'queue stays ahead of results; close and system back keep remaining awards pending',
    (tester) async {
      var current = [
        badge(AchievementId.streak, 0),
        badge(AchievementId.attempts, 0),
      ];
      final service = AchievementAwardService(
        scope: 'ab',
        load: () async => current,
      );
      await service.prepare();
      current = [
        badge(AchievementId.streak, 3),
        badge(AchievementId.attempts, 3),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: CompletionAchievementAwards(
            service: service,
            resultBuilder: (_) => const Scaffold(body: Text('result')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Без пропусков'), findsOneWidget);
      expect(find.text('result'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('result'), findsOneWidget);
      expect((await service.pending()).single.id, AchievementId.attempts);
    },
  );

  for (final exam in [false, true]) {
    testWidgets(
      '${exam ? 'exam' : 'training'} never interrupts answers and delays review until all awards close',
      (tester) async {
        final data = ProgressDataSource();
        await data.init();
        // The first answer reaches a tier while the user is still studying.
        for (var i = 0; i < 99; i++) {
          await data.saveAnswer(
            questionId: 'old',
            isCorrect: true,
            selectedAnswerIndex: 0,
            category: TicketCategory.ab,
          );
        }
        var requests = 0;
        final review = ReviewPromptService.forTesting(
          platform: TargetPlatform.iOS,
          isAvailable: () async => true,
          requestReview: () async {
            requests++;
          },
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              progressDataSourceProvider.overrideWithValue(data),
              ttsServiceProvider.overrideWithValue(_SilentTts()),
              reviewPromptServiceProvider.overrideWithValue(review),
              statsProvider.overrideWith(
                (ref) async => {'totalQuestions': 800, 'totalTickets': 40},
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: exam
                  ? ExamScreen(
                      allQuestions: questions(),
                      rules: const ExamRules(
                        mainCount: 2,
                        totalSeconds: 600,
                        maxMistakes: 0,
                        additionalPerMistake: 0,
                        additionalSecondsPerBlock: 0,
                      ),
                    )
                  : TrainingScreen(questions: questions(), title: 'Билет 1'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (var i = 0; i < 2; i++) {
          await tester.tap(find.text('Верный ответ').hitTestable());
          await tester.pumpAndSettle();
          if (!exam || i == 0) {
            expect(find.byType(AchievementAwardScreen), findsNothing);
            expect(requests, 0);
          }
          if (!exam) {
            await tester.tap(
              find.text(i == 0 ? 'Следующий вопрос' : 'Завершить'),
            );
            await tester.pumpAndSettle();
          }
        }
        expect(find.byType(StreakCelebrationView), findsOneWidget);
        expect(find.byType(AchievementAwardScreen), findsNothing);
        expect(requests, 0);
        await tester.tap(find.text('Продолжить'));
        await tester.pumpAndSettle();
        expect(find.byType(AchievementAwardScreen), findsOneWidget);
        expect(find.text('Неутомимый'), findsOneWidget);
        expect(requests, 0);
        final expectedAwards = exam ? 3 : 1;
        for (var i = 0; i < expectedAwards; i++) {
          expect(requests, 0);
          await tester.tap(find.text('Продолжить'));
          await tester.pumpAndSettle();
        }
        expect(find.byType(AchievementAwardScreen), findsNothing);
        expect(requests, 1);
        if (exam) {
          expect(find.text('Экзамен сдан!'), findsOneWidget);
        } else {
          expect(find.byType(TrainingResultScreen), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'native result receives thresholds and persists presented awards before booking the round',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      GodotGame.resetForTest();
      final data = ProgressDataSource();
      await data.init();
      final awards = AchievementAwardService(
        scope: 'native',
        load: () async => [
          AchievementProgress(
            id: AchievementId.trafficController,
            levels: AchievementThresholds.trafficController,
            value: data.getTrafficControllerProgress().bestScore,
          ),
        ],
      );
      List<String>? launch;
      const channel = MethodChannel('pdd/godot_game');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method != 'start') return null;
            launch = ((call.arguments as Map)['args'] as List).cast<String>();
            return jsonEncode({
              'game': 'regulator',
              'runs': [
                {
                  'id': 'one',
                  'score': 200,
                  'solved': 8,
                  'wrong': 0,
                  'combo': 8,
                  'finished': true,
                },
              ],
              'achievement_awards': {'trafficController': 1},
            });
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            progressDataSourceProvider.overrideWithValue(data),
            achievementAwardServiceProvider.overrideWithValue(awards),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => GodotGame.playRegulator(context, ref),
                child: const Text('start'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('start'));
      await tester.pumpAndSettle();
      final payload =
          jsonDecode(
                launch!
                    .singleWhere(
                      (arg) => arg.startsWith('--achievement-awards='),
                    )
                    .substring('--achievement-awards='.length),
              )
              as Map;
      expect(payload['game'], 'trafficController');
      expect(
        (payload['items'] as List).single['levels'],
        AchievementThresholds.trafficController,
      );
      expect((payload['shown'] as Map)['trafficController'], 0);
      expect((await awards.receipts())['trafficController'], 1);
      expect(await awards.pending(), isEmpty);
      expect(find.byType(AchievementAwardScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    },
  );

  for (final config in [
    (
      name: 'phone',
      size: const Size(390, 844),
      scale: 1.0,
      lang: 'ru',
      dark: false,
    ),
    (
      name: 'compact',
      size: const Size(320, 568),
      scale: 2.0,
      lang: 'kk',
      dark: false,
    ),
    (
      name: 'landscape',
      size: const Size(844, 390),
      scale: 1.6,
      lang: 'en',
      dark: false,
    ),
    (
      name: 'dark',
      size: const Size(414, 896),
      scale: 1.0,
      lang: 'ru',
      dark: true,
    ),
  ]) {
    for (final flame in [false, true]) {
      testWidgets(
        '${flame ? 'streak' : 'award'} layout and accessible actions ${config.name}',
        (tester) async {
          updateAppLocale(Locale(config.lang));
          addTearDown(() => updateAppLocale(const Locale('ru')));
          tester.view.physicalSize = config.size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final key = GlobalKey();
          var continued = 0, closed = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: config.dark ? AppTheme.darkTheme : AppTheme.lightTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(config.scale),
                  disableAnimations: true,
                ),
                child: RepaintBoundary(key: key, child: child!),
              ),
              home: flame
                  ? StreakCelebrationView(
                      streak: Streak(
                        current: 7,
                        longest: 7,
                        lastActiveDate: DateTime.now(),
                        startDate: DateTime.now(),
                        activeDays: const {},
                      ),
                      onContinue: () => continued++,
                      onClose: () => closed++,
                      position: 1,
                      total: 3,
                    )
                  : AchievementAwardScreen(
                      achievement: badge(AchievementId.streak, 30),
                      onContinue: () => continued++,
                      onClose: () => closed++,
                      position: 1,
                      total: 2,
                    ),
            ),
          );
          await tester.pumpAndSettle();
          final next = find.text(appL10n.continueButton);
          expect(next.hitTestable(), findsOneWidget);
          await tester.tap(next);
          await tester.tap(find.byTooltip(appL10n.close));
          expect(continued, 1);
          expect(closed, 1);
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('PDD_CAPTURE_ACHIEVEMENTS')) {
            if (!flame) {
              await tester.runAsync(() async {
                await precacheImage(
                  tester.widget<Image>(find.byType(Image).first).image,
                  tester.element(find.byType(AchievementAwardScreen)),
                );
              });
            }
            await tester.pumpAndSettle();
            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary;
              final pixels = await boundary.toImage(pixelRatio: 2);
              final bytes = await pixels.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                'output/achievement-awards/${flame ? 'streak-' : ''}${config.name}.png',
              );
              file.parent.createSync(recursive: true);
              file.writeAsBytesSync(bytes!.buffer.asUint8List());
              pixels.dispose();
            });
          }
        },
      );
    }
  }

  testWidgets('rays keep moving and stop when reduced motion is enabled', (
    tester,
  ) async {
    var reduced = false;
    Widget screen() => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: child!,
      ),
      home: CelebrationScreen(
        heading: 'Heading',
        title: 'Award',
        description: 'Description',
        label: '1 / 4',
        heroBuilder: (size) => SizedBox.square(dimension: size),
        onContinue: () {},
        onClose: () {},
      ),
    );
    await tester.pumpWidget(screen());
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, isTrue);
    reduced = true;
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
