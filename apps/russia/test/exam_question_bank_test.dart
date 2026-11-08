import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/data/models/exam_question_bank.dart';
import 'package:pdd_app/data/models/question.dart';

List<Map<String, dynamic>> realQuestions(String category) {
  final data =
      jsonDecode(
            File(
              'assets/countries/ru/questions/questions_$category.json',
            ).readAsStringSync(),
          )
          as Map;
  return (data['tickets'] as List).expand((ticket) {
    final questions = ticket['questions'] as List;
    return questions.asMap().entries.map(
      (entry) => <String, dynamic>{
        ...Map<String, dynamic>.from(entry.value as Map),
        'id': entry.value['variantId'] ?? entry.value['id'],
        'ticketNumber': ticket['number'],
        'questionNumber': entry.key + 1,
      },
    );
  }).toList();
}

void main() {
  test(
    'legacy Question.toMap zero position preserves ordered source blocks',
    () {
      final questions = <Map<String, dynamic>>[
        for (var ticket = 1; ticket <= 2; ticket++)
          for (var position = 1; position <= 20; position++)
            Question(
              id: '$ticket:$position',
              question: 'Source $position',
              answers: [const Answer(text: 'yes', isCorrect: true)],
              ticketNumber: ticket,
            ).toMap(),
      ];
      expect(questions.every((q) => q['questionNumber'] == 0), isTrue);
      final bank = ExamQuestionBank(questions, CountryConfig.current.examRules);
      final main = bank.mainQuestions(Random(1));
      expect(main, hasLength(20));
      for (var group = 0; group < 4; group++) {
        final block = main.sublist(group * 5, group * 5 + 5);
        expect(block.map((q) => q['ticketNumber']).toSet(), hasLength(1));
        expect(
          block.map((q) => q['questionNumber']),
          List.generate(5, (i) => group * 5 + i + 1),
        );
      }
      final extra = bank.additionalQuestions(
        groups: [0],
        usedIds: main.map((q) => q['id'] as String).toSet(),
        random: Random(2),
      );
      expect(extra, hasLength(5));
      expect(extra.map((q) => q['questionNumber']), [1, 2, 3, 4, 5]);
      expect(
        extra.every((q) => !main.any((used) => used['id'] == q['id'])),
        isTrue,
      );
    },
  );
  for (final category in ['ab', 'cd']) {
    test('$category actual corpus generates intact ordered source blocks', () {
      final questions = realQuestions(category);
      final bank = ExamQuestionBank(questions, CountryConfig.current.examRules);
      for (var seed = 0; seed < 100; seed++) {
        final exam = bank.mainQuestions(Random(seed));
        expect(exam.length, 20);
        for (var group = 0; group < 4; group++) {
          final block = exam.sublist(group * 5, group * 5 + 5);
          expect(block.map((q) => q['ticketNumber']).toSet(), hasLength(1));
          expect(
            block.map((q) => q['questionNumber']),
            List.generate(5, (i) => group * 5 + i + 1),
          );
          expect(block.map((q) => q['examGroup']).toSet(), {group});
        }
      }
    });

    test(
      '$category errors receive other intact blocks from the same source groups',
      () {
        final bank = ExamQuestionBank(
          realQuestions(category),
          CountryConfig.current.examRules,
        );
        for (var seed = 0; seed < 100; seed++) {
          final main = bank.mainQuestions(Random(seed));
          final usedIds = main.map((q) => q['id'] as String).toSet();
          final extra = bank.additionalQuestions(
            groups: [2, 0],
            usedIds: usedIds,
            random: Random(seed + 1),
          );
          expect(extra.length, 10);
          expect(extra.any((q) => usedIds.contains(q['id'])), isFalse);
          for (var i = 0; i < 2; i++) {
            final group = [2, 0][i];
            final block = extra.sublist(i * 5, i * 5 + 5);
            expect(block.map((q) => q['ticketNumber']).toSet(), hasLength(1));
            expect(
              block.map((q) => q['questionNumber']),
              List.generate(5, (n) => group * 5 + n + 1),
            );
          }
        }
      },
    );
  }
}
