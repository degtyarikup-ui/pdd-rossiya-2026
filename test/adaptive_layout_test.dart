import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdd_app/core/layout/app_content_frame.dart';
import 'package:pdd_app/core/layout/app_max_width_frame.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/models/app_settings.dart';
import 'package:pdd_app/data/models/question.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/exam/exam_screen.dart';
import 'package:pdd_app/presentation/screens/home/home_screen.dart';
import 'package:pdd_app/presentation/screens/settings/settings_screen.dart';
import 'package:pdd_app/presentation/screens/signs/signs_screen.dart';
import 'package:pdd_app/presentation/screens/tickets/tickets_screen.dart';
import 'package:pdd_app/presentation/screens/topics/topics_screen.dart';
import 'package:pdd_app/presentation/screens/training/training_result_screen.dart';
import 'package:pdd_app/presentation/screens/training/training_screen.dart';
import 'package:pdd_app/presentation/widgets/question_content_layout.dart';
import 'helpers/achievement_awards.dart';

class _SilentTts implements TtsService {
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
  @override
  Future<void> stop() async {}
  @override
  Future<void> updateLanguage(String lang) async {}
  @override
  Future<void> dispose() async {}
}

List<Map<String, dynamic>> _questions() => List.generate(
  20,
  (i) => {
    'id': 'adaptive-$i',
    'question':
        'Вопрос ${i + 1}: в каком случае разрешено продолжить движение через перекрёсток?',
    'answers': [
      {'text': 'Верный ответ', 'correct': true},
      {
        'text':
            'Другой ответ с длинным объяснением условий движения через перекрёсток',
        'correct': false,
      },
      {'text': 'Последний вариант ответа', 'correct': false},
    ],
    'comment': 'Объяснение ответа на вопрос. ' * 12,
    'pddPoints': <String>[],
    'image': null,
    'topic': <String>[],
    'ticketNumber': 1,
  },
);

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
  });
  tearDown(() => updateAppLocale(const Locale('ru')));

  void viewport(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> open(
    WidgetTester tester,
    Widget screen, {
    double scale = 1,
    String locale = 'ru',
    GlobalKey<NavigatorState>? navigator,
    bool confirm = false,
  }) async {
    SharedPreferences.setMockInitialValues({'notification_prompt_shown': true});
    final data = ProgressDataSource();
    await data.init();
    await data.saveAppSettings(
      AppSettings(
        languageCode: locale,
        soundEffectsEnabled: false,
        confirmAnswerEnabled: confirm,
      ),
    );
    SoundEffectsService.instance.setEnabled(false);
    updateAppLocale(Locale(locale));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          noAchievementAwards,
          progressDataSourceProvider.overrideWithValue(data),
          ttsServiceProvider.overrideWithValue(_SilentTts()),
          isAuthenticatedProvider.overrideWithValue(false),
          currentUserProvider.overrideWithValue(null),
          statsProvider.overrideWith(
            (_) async => {
              'correctAnswers': 138,
              'answeredQuestions': 252,
              'wrongQuestions': 114,
              'passedTickets': 1,
              'totalQuestions': 800,
              'totalTickets': 40,
            },
          ),
          unfinishedSessionProvider.overrideWith((_) async => null),
          ticketsProvider.overrideWith(
            (_) async => List.generate(
              40,
              (i) => {
                'number': i + 1,
                'questions': _questions().map(Question.fromJson).toList(),
              },
            ),
          ),
          topicsProvider.overrideWith(
            (_) async => List.generate(
              5,
              (i) => {
                'name': 'Тема ${i + 1}',
                'questions': _questions().map(Question.fromJson).toList(),
              },
            ),
          ),
        ],
        child: MaterialApp(
          navigatorKey: navigator,
          theme: scale == 2 ? AppTheme.darkTheme : AppTheme.lightTheme,
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              // Landscape notches matter independently of window width.
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            ),
            child: AppMaxWidthFrame(child: child),
          ),
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(568, 320),
    const Size(667, 375),
    const Size(844, 390),
    const Size(600, 960),
    const Size(768, 1024),
    const Size(1024, 768),
    const Size(1440, 900),
  ]) {
    for (final scale in [1.0, 2.0]) {
      for (final exam in [false, true]) {
        testWidgets(
          '${exam ? 'exam' : 'training'} $size text $scale: all answers reachable',
          (tester) async {
            viewport(tester, size);
            final questions = _questions();
            await open(
              tester,
              exam
                  ? ExamScreen(allQuestions: questions)
                  : TrainingScreen(questions: questions, title: 'Билет 1'),
              scale: scale,
            );
            expect(tester.takeException(), isNull);
            final last = find.text('Последний вариант ответа').first;
            // Scroll the answer column without asking the horizontal PageView
            // to reveal the text's horizontal position as a different page.
            await Scrollable.of(
              tester.element(last),
            ).position.ensureVisible(tester.renderObject(last), alignment: .5);
            await tester.pumpAndSettle();
            expect(last.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final exam in [false, true]) {
    testWidgets(
      '${exam ? 'exam' : 'training'} retains route, page, selection and timer across rotation',
      (tester) async {
        viewport(tester, const Size(390, 844));
        final navigator = GlobalKey<NavigatorState>();
        await open(
          tester,
          const Scaffold(body: Text('root')),
          navigator: navigator,
          confirm: true,
        );
        final questions = _questions();
        navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => exam
                ? ExamScreen(allQuestions: questions)
                : TrainingScreen(questions: questions, title: 'Билет 1'),
          ),
        );
        await tester.pumpAndSettle();
        final screen = find.byType(exam ? ExamScreen : TrainingScreen);
        final state = tester.state(screen);
        final controller = tester
            .widget<PageView>(find.byType(PageView))
            .controller!;
        // The exam allows navigating before submitting an answer.
        if (exam) {
          controller.jumpToPage(2);
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Верный ответ').hitTestable());
        await tester.pumpAndSettle();
        if (exam) {
          controller.jumpToPage(2);
          await tester.pumpAndSettle();
        }
        final confirmation = find.widgetWithText(
          ElevatedButton,
          appL10n.confirmAnswerButton,
        );
        if (!exam) {
          expect(
            tester.widget<ElevatedButton>(confirmation).onPressed,
            isNotNull,
          );
        }
        for (final size in [
          const Size(844, 390),
          const Size(1024, 768),
          const Size(390, 844),
        ]) {
          tester.view.physicalSize = size;
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpAndSettle();
          expect(tester.state(screen), same(state));
          expect(
            tester.widget<PageView>(find.byType(PageView)).controller,
            same(controller),
          );
          expect(controller.page, closeTo(exam ? 2 : 0, .01));
          expect(navigator.currentState!.canPop(), isTrue);
          if (exam) {
            final answer = find.ancestor(
              of: find.text('Верный ответ').hitTestable(),
              matching: find.byType(InkWell),
            );
            expect(
              tester.widget<InkWell>(answer).onTap,
              isNull,
              reason: 'The submitted answer must remain submitted',
            );
          } else {
            expect(
              tester.widget<ElevatedButton>(confirmation).onPressed,
              isNotNull,
            );
          }
          expect(tester.takeException(), isNull);
        }
        if (exam) {
          expect(
            find.text('20:00'),
            findsNothing,
            reason: 'Rotation must not restart the timer',
          );
        }
        if (!exam) await tester.tap(confirmation);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final locale in ['ru', 'en', 'kk']) {
    for (final scale in [1.0, 2.0]) {
      for (final size in [const Size(844, 390), const Size(768, 1024)]) {
        testWidgets('home and result $locale $size text $scale', (
          tester,
        ) async {
          viewport(tester, size);
          await open(tester, const HomeScreen(), locale: locale, scale: scale);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await open(
            tester,
            TrainingResultScreen(
              title: 'Билет 1',
              total: 20,
              correct: 19,
              wrongQuestions: _questions().take(1).toList(),
            ),
            locale: locale,
            scale: scale,
          );
          expect(tester.takeException(), isNull);
          final done = find.widgetWithText(ElevatedButton, appL10n.done);
          await tester.ensureVisible(done);
          await tester.pumpAndSettle();
          expect(done.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('catalogues gain columns while reading pages stay constrained', (
    tester,
  ) async {
    viewport(tester, const Size(1024, 768));
    await open(tester, const TicketsScreen());
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    final grid = tester.widget<GridView>(find.byType(GridView));
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      4,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await open(tester, const TopicsScreen());
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await open(tester, const SettingsScreen());
    expect(
      tester.getSize(find.byType(Scaffold)).width,
      AppContentFrame.readingWidth,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide questions use two independently scrollable columns', (
    tester,
  ) async {
    viewport(tester, const Size(1024, 768));
    await open(
      tester,
      TrainingScreen(questions: _questions(), title: 'Билет 1'),
    );
    expect(find.byKey(const ValueKey('question-wide-layout')), findsOneWidget);
    final question = tester.getRect(
      find.text(_questions().first['question'] as String),
    );
    final answer = tester.getRect(find.text('Верный ответ').first);
    expect(question.right, lessThan(answer.left));
    expect(
      find.descendant(
        of: find.byType(QuestionContentLayout).first,
        matching: find.byType(SingleChildScrollView),
      ),
      findsNWidgets(2),
    );
  });

  for (final locale in ['ru', 'en', 'kk']) {
    for (final size in [const Size(844, 390), const Size(768, 1024)]) {
      testWidgets('catalogues $locale $size with 200% text remain usable', (
        tester,
      ) async {
        viewport(tester, size);
        await open(tester, const TicketsScreen(), locale: locale, scale: 2);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('№40'),
          250,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        expect(find.text('№40').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await open(tester, const TopicsScreen(), locale: locale, scale: 2);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await open(
          tester,
          SignCategoryScreen(
            categoryName: 'Предупреждающие знаки',
            signs: {
              for (var i = 1; i <= 12; i++)
                '1.$i': {'name': 'Дорожный знак с длинным названием'},
            },
          ),
          locale: locale,
          scale: 2,
        );
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('1.12'),
          250,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        expect(find.text('1.12').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'window metrics and safe insets match the constrained app canvas',
    (tester) async {
      viewport(tester, const Size(1440, 900));
      late MediaQueryData media;
      await open(
        tester,
        Builder(
          builder: (context) {
            media = MediaQuery.of(context);
            return const Scaffold();
          },
        ),
      );
      expect(media.size.width, 1200);
      expect(media.padding.left, 0);
      expect(media.padding.right, 0);
      expect(media.padding.top, 24);
    },
  );
}
