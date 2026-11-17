import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/question.dart';
import 'package:pdd_app/domain/services/mistakes_test_generator.dart';

Question _q(
  String id, {
  List<String> topics = const ['Проезд перекрестков'],
  int ticket = 1,
  int number = 1,
}) {
  return Question(
    id: id,
    question: 'Вопрос $id',
    answers: const [
      Answer(text: 'Да', isCorrect: true),
      Answer(text: 'Нет', isCorrect: false),
    ],
    topic: topics,
    ticketNumber: ticket,
    questionNumber: number,
  );
}

void main() {
  group('MistakesAnalysis', () {
    test(
      'invalid imported counters cannot crash or create negative history',
      () {
        final analysis = MistakesAnalysis.build(
          allQuestions: [_q('q1'), _q('q2'), _q('q3')],
          progress: {
            'q1': {
              'isCorrect': false,
              'wrongAttempts': '2',
              'attemptsCount': '3',
            },
            'q2': {'isCorrect': true, 'wrongAttempts': -2, 'attemptsCount': -1},
            'q3': {
              'isCorrect': false,
              'wrongAttempts': double.infinity,
              'attemptsCount': double.nan,
            },
          },
        );
        expect(analysis.entriesById['q1']!.wrongAttempts, 1);
        expect(analysis.entriesById['q1']!.attemptsCount, 1);
        expect(analysis.entriesById['q2']!.wrongAttempts, 0);
        expect(analysis.entriesById['q2']!.attemptsCount, 1);
        expect(analysis.entriesById['q3']!.wrongAttempts, 1);
        expect(analysis.weakTopics.single.mistakeAttempts, 2);
      },
    );

    test(
      'deduplicates questions and tracks active, historical, and topic stats',
      () {
        final bank = [
          _q('q1', topics: ['Перекрестки', 'Знаки'], ticket: 1, number: 1),
          // Дубль того же id в другом билете не должен удваивать ошибки.
          _q('q1', topics: ['Перекрестки', 'Знаки'], ticket: 2, number: 1),
          _q('q2', topics: ['Перекрестки'], ticket: 1, number: 2),
          _q('q3', topics: ['Знаки'], ticket: 1, number: 3),
          _q('q4', topics: ['Разметка'], ticket: 1, number: 4),
        ];

        final progress = <String, dynamic>{
          // Исправленный вопрос с 3 ошибками в истории.
          'q1': {
            'isCorrect': true,
            'wrongAttempts': 3,
            'attemptsCount': 4,
            'answeredAt': '2026-11-10T10:00:00Z',
          },
          // Устаревшая запись с неверным ответом без поля wrongAttempts.
          'q2': {'isCorrect': false, 'answeredAt': '2026-11-11T10:00:00Z'},
        };

        final analysis = MistakesAnalysis.build(
          allQuestions: bank,
          progress: progress,
          activeWrongIds: ['q2', 'q3'],
        );

        expect(analysis.allUniqueQuestions.map((q) => q.id), [
          'q1',
          'q2',
          'q3',
          'q4',
        ]);
        expect(analysis.activeMistakes.map((e) => e.question.id), ['q2', 'q3']);
        expect(analysis.frequentMistakes.map((e) => e.question.id), [
          'q1',
          'q2',
          'q3',
        ]);
        expect(analysis.hasDrillableFrequentMistakes, isTrue);

        // Перекрестки: q1 (3) + q2 (1) = 4 ошибки; Знаки: q1 (3) + q3 (1) = 4;
        // при равенстве mistakeAttempts выше тема с большим activeMistakeCount (Знаки: 1, Перекрестки: 1 -> алфавит).
        expect(analysis.weakTopics.map((t) => t.name).toList(), [
          'Знаки',
          'Перекрестки',
        ]);
        final cross = analysis.weakTopics.firstWhere(
          (t) => t.name == 'Перекрестки',
        );
        expect(cross.mistakeAttempts, 4);
        expect(cross.activeMistakeCount, 1);
        expect(cross.mistakeQuestionCount, 2);
        expect(cross.totalQuestions, 2);
        expect(cross.unseenCount, 0);
      },
    );

    test(
      'hasDrillableFrequentMistakes is false for single first-time active mistakes',
      () {
        final bank = [_q('q1'), _q('q2')];
        final analysis = MistakesAnalysis.build(
          allQuestions: bank,
          progress: {
            'q1': {'isCorrect': false, 'wrongAttempts': 1, 'attemptsCount': 1},
          },
          activeWrongIds: ['q1'],
        );
        expect(analysis.hasAnyHistory, isTrue);
        expect(analysis.hasDrillableFrequentMistakes, isFalse);
      },
    );
  });

  group('MistakesTestGenerator', () {
    test(
      'generateFrequentMistakesTest mixes frequent mistakes with unseen questions from weak topics proportionally',
      () {
        final bank = <Question>[
          // Слабая тема A (15 вопросов, много ошибок)
          for (var i = 0; i < 15; i++) _q('a$i', topics: ['Тема A']),
          // Слабая тема B (10 вопросов, меньше ошибок)
          for (var i = 0; i < 10; i++) _q('b$i', topics: ['Тема B']),
          // Сильная тема C (15 вопросов, без ошибок)
          for (var i = 0; i < 15; i++) _q('c$i', topics: ['Тема C']),
        ];

        final progress = <String, dynamic>{
          'a0': {'isCorrect': false, 'wrongAttempts': 4, 'attemptsCount': 5},
          'a1': {'isCorrect': true, 'wrongAttempts': 2, 'attemptsCount': 3},
          'b0': {'isCorrect': false, 'wrongAttempts': 1, 'attemptsCount': 1},
          // Один изученный вопрос без ошибок в теме A
          'a2': {'isCorrect': true, 'wrongAttempts': 0, 'attemptsCount': 1},
        };

        final analysis = MistakesAnalysis.build(
          allQuestions: bank,
          progress: progress,
          activeWrongIds: ['a0', 'b0'],
        );

        final testQuestions =
            MistakesTestGenerator.generateFrequentMistakesTest(
              analysis,
              targetCount: 20,
              random: Random(42),
            );

        expect(testQuestions, hasLength(20));
        expect(testQuestions.map((q) => q.id).toSet(), hasLength(20));
        // Должны войти сами частые ошибки
        expect(testQuestions.map((q) => q.id), containsAll(['a0', 'a1', 'b0']));
        // Все 20 вопросов могут быть набраны из слабых тем A и B (15 + 10 = 25),
        // не залезая в сильную тему C, и с перевесом в пользу темы A.
        final countA = testQuestions
            .where((q) => q.topic.contains('Тема A'))
            .length;
        final countB = testQuestions
            .where((q) => q.topic.contains('Тема B'))
            .length;
        final countC = testQuestions
            .where((q) => q.topic.contains('Тема C'))
            .length;
        expect(countC, 0);
        expect(countA, greaterThan(countB));
      },
    );

    test(
      'generateFrequentMistakesTest falls back to general bank when weak topics are small',
      () {
        final bank = <Question>[
          _q('a0', topics: ['Малая тема']),
          _q('a1', topics: ['Малая тема']),
          for (var i = 0; i < 10; i++) _q('other$i', topics: ['Другая тема']),
        ];
        final analysis = MistakesAnalysis.build(
          allQuestions: bank,
          progress: {
            'a0': {'isCorrect': false, 'wrongAttempts': 2, 'attemptsCount': 2},
          },
          activeWrongIds: ['a0'],
        );

        final generated = MistakesTestGenerator.generateFrequentMistakesTest(
          analysis,
          targetCount: 8,
          random: Random(1),
        );

        expect(generated, hasLength(8));
        expect(generated.map((q) => q.id).toSet(), hasLength(8));
        expect(generated.map((q) => q.id), containsAll(['a0', 'a1']));
      },
    );

    test(
      'generateFrequentMistakesTest returns empty when user has no mistakes',
      () {
        final analysis = MistakesAnalysis.build(
          allQuestions: [_q('q1'), _q('q2')],
          progress: {
            'q1': {'isCorrect': true, 'wrongAttempts': 0, 'attemptsCount': 1},
          },
        );
        expect(
          MistakesTestGenerator.generateFrequentMistakesTest(analysis),
          isEmpty,
        );
      },
    );

    test(
      'generateTopicTest prioritizes mistakes and unseen questions in the topic',
      () {
        final bank = <Question>[
          for (var i = 0; i < 25; i++) _q('t$i', topics: ['Сложная тема']),
        ];
        final progress = <String, dynamic>{
          't0': {'isCorrect': false, 'wrongAttempts': 2, 'attemptsCount': 2},
          't1': {'isCorrect': true, 'wrongAttempts': 1, 'attemptsCount': 2},
          for (var i = 2; i < 20; i++)
            't$i': {
              'isCorrect': true,
              'wrongAttempts': 0,
              'attemptsCount': 1,
              'answeredAt': '2026-11-${(i % 9) + 10}T10:00:00Z',
            },
        };
        // t20..t24 — неизученные вопросы темы.
        final analysis = MistakesAnalysis.build(
          allQuestions: bank,
          progress: progress,
          activeWrongIds: ['t0'],
        );

        final topic = analysis.weakTopics.single;
        final generated = MistakesTestGenerator.generateTopicTest(
          analysis,
          topic,
          maxQuestions: 10,
          random: Random(7),
        );

        expect(generated, hasLength(10));
        final ids = generated.map((q) => q.id).toSet();
        expect(ids, hasLength(10));
        // Обязаны попасть активная и прошлая ошибки (t0, t1) и все 5 неизученных (t20..t24)
        expect(
          ids,
          containsAll(['t0', 't1', 't20', 't21', 't22', 't23', 't24']),
        );
      },
    );
  });
}
