import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/data/models/question.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/data/services/usage_reporter.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/data/sources/questions_data_source.dart';
import 'package:pdd_app/l10n/gen/app_localizations.dart';
import 'package:pdd_app/presentation/screens/mistakes/mistakes_screen.dart';
import 'package:pdd_app/presentation/screens/training/training_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/achievement_awards.dart';

class _SilentTts implements TtsService {
  @override
  ValueListenable<NarrationStatus> get status =>
      ValueNotifier(NarrationStatus.idle);
  @override
  Future<void> setAppActive(bool active) async {}
  @override
  Future<void> configure({
    required bool enabled,
    required double speed,
  }) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<Duration?> remainingPlaybackDuration() async => null;
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

class _FakeQuestionsBank extends QuestionsDataSource {
  _FakeQuestionsBank(this.questions);
  final List<Question> questions;

  @override
  Future<List<Question>> loadTickets(
    TicketCategory category, [
    String? lang,
  ]) async => questions;
}

Question _makeQuestion(String id, String topic, int number) {
  return Question(
    id: id,
    question: 'Текст вопроса $id',
    answers: const [
      Answer(text: 'Верно', isCorrect: true),
      Answer(text: 'Неверно', isCorrect: false),
    ],
    topic: [topic],
    ticketNumber: 1,
    questionNumber: number,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpMistakes(
    WidgetTester tester, {
    required List<Question> bank,
    Map<String, dynamic> progress = const {},
    String language = 'ru',
    double textScale = 1,
    Size size = const Size(412, 915),
  }) async {
    SharedPreferences.setMockInitialValues({
      if (progress.isNotEmpty) 'question_progress_ab': jsonEncode(progress),
    });
    final data = ProgressDataSource();
    await data.init();

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          noAchievementAwards,
          progressDataSourceProvider.overrideWithValue(data),
          questionsDataSourceProvider.overrideWithValue(
            _FakeQuestionsBank(bank),
          ),
          ttsServiceProvider.overrideWithValue(_SilentTts()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const MistakesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows empty state when there are no active or past mistakes', (
    tester,
  ) async {
    final bank = [_makeQuestion('q1', 'Знаки', 1)];
    await pumpMistakes(
      tester,
      bank: bank,
      progress: {
        'q1': {
          'isCorrect': true,
          'wrongAttempts': 0,
          'attemptsCount': 1,
          'answeredAt': '2026-11-10T10:00:00Z',
        },
      },
    );
    expect(find.text('Ошибок пока нет'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mistakes-general-test-card')),
      findsNothing,
    );
  });

  testWidgets(
    'shows general test, hardest drill, and weak topics when active mistakes are cleared but history exists',
    (tester) async {
      final bank = [
        for (var i = 0; i < 12; i++)
          _makeQuestion('s$i', 'Дорожные знаки', i + 1),
        for (var i = 0; i < 6; i++)
          _makeQuestion('p$i', 'Проезд перекрестков', i + 1),
      ];
      await pumpMistakes(
        tester,
        bank: bank,
        progress: {
          's0': {
            'isCorrect': true,
            'wrongAttempts': 3,
            'attemptsCount': 4,
            'answeredAt': '2026-11-10T10:00:00Z',
          },
          'p0': {
            'isCorrect': true,
            'wrongAttempts': 1,
            'attemptsCount': 2,
            'answeredAt': '2026-11-10T11:00:00Z',
          },
        },
      );

      expect(
        find.byKey(const ValueKey('mistakes-general-test-card')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mistakes-hardest-card')),
        findsOneWidget,
      );
      expect(find.text('Дорожные знаки'), findsOneWidget);
      expect(find.text('Проезд перекрестков'), findsOneWidget);
      expect(find.text('Текущие ошибки исправлены'), findsOneWidget);
      expect(find.text('Повторить все ошибки'), findsNothing);

      // Нажатие на общий тест открывает TrainingScreen с вопросами из банка (включая новые)
      final sent = <Map>[];
      final reporter = UsageReporter(
        endpoint: 'https://test',
        secret: 'test',
        client: MockClient((r) async {
          sent.add(jsonDecode(r.body) as Map);
          return http.Response('{}', 200);
        }),
      );
      UsageReporter.setInstanceForTest(reporter);
      addTearDown(() => UsageReporter.setInstanceForTest(null));

      await tester.tap(
        find.byKey(const ValueKey('mistakes-general-test-card')),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(reporter.flush);

      final training = tester.widget<TrainingScreen>(
        find.byType(TrainingScreen),
      );
      expect(training.questions.length, 18);
      expect(training.title, 'Общий тест по частым ошибкам');
      expect(sent.expand((b) => b['events'] as List).map((e) => e['feature']), [
        'mistakes',
      ]);
    },
  );

  testWidgets('tapping a weak topic launches a generated test on that topic', (
    tester,
  ) async {
    final bank = [
      for (var i = 0; i < 8; i++) _makeQuestion('s$i', 'Дорожные знаки', i + 1),
      for (var i = 0; i < 5; i++)
        _makeQuestion('p$i', 'Проезд перекрестков', i + 1),
    ];
    await pumpMistakes(
      tester,
      bank: bank,
      progress: {
        's0': {
          'isCorrect': false,
          'wrongAttempts': 2,
          'attemptsCount': 2,
          'answeredAt': '2026-11-10T10:00:00Z',
        },
      },
    );

    expect(find.text('Ошибок: 2'), findsOneWidget);
    expect(find.text('Повторить все ошибки'), findsOneWidget);

    await tester.tap(find.text('Дорожные знаки').first);
    await tester.pumpAndSettle();

    final training = tester.widget<TrainingScreen>(find.byType(TrainingScreen));
    expect(training.title, 'Дорожные знаки');
    expect(training.questions, hasLength(8));
    expect(
      training.questions.every(
        (q) => (q['topic'] as List).contains('Дорожные знаки'),
      ),
      isTrue,
    );
  });

  for (final lang in ['ru', 'en', 'kk']) {
    testWidgets('$lang fits 320px at double text size without overflow', (
      tester,
    ) async {
      final bank = [
        for (var i = 0; i < 6; i++)
          _makeQuestion('q$i', 'Длинное название темы номер $i', i + 1),
      ];
      await pumpMistakes(
        tester,
        bank: bank,
        progress: {
          'q0': {
            'isCorrect': false,
            'wrongAttempts': 3,
            'attemptsCount': 4,
            'answeredAt': '2026-11-10T10:00:00Z',
          },
          'q1': {
            'isCorrect': true,
            'wrongAttempts': 2,
            'attemptsCount': 3,
            'answeredAt': '2026-11-10T10:05:00Z',
          },
        },
        language: lang,
        textScale: 2.0,
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
