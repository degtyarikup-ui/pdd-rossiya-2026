import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/data/models/exam_question_bank.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'exam_flow_test.dart' as harness;
import 'exam_question_bank_test.dart' show realQuestions;

void main() {
  testWidgets(
    'resumed actual exam can draw and persist its correct extra group',
    (tester) async {
      final all = realQuestions('ab')
          .map(
            (q) => <String, dynamic>{
              ...q,
              'image': null,
              'answers': [
                {'text': 'Верный ответ', 'correct': true},
                {'text': 'Неверный ответ', 'correct': false},
              ],
            },
          )
          .toList();
      final main = ExamQuestionBank(
        all,
        CountryConfig.current.examRules,
      ).mainQuestions(Random(4));
      final answers = List<int?>.filled(20, 0);
      answers[0] = 1;
      answers[19] = null;
      final source = await harness.pumpExam(
        tester,
        questions: all,
        resume: {
          'questions': main,
          'answers': answers,
          'index': 19,
          'examGroups': main.map((q) => q['examGroup']).toList(),
          'remainingSeconds': 1000,
          'totalSeconds': 1200,
          'additionalPhase': false,
          'additionalQuestionsCount': 0,
          'initialWrongCount': 0,
        },
      );
      await harness.answerCurrent(tester, correct: true);
      expect(find.text('Дополнительные вопросы'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();
      final saved = source.loadUnfinishedSession(TicketCategory.ab)!;
      expect(saved['questionIds'], hasLength(25));
      expect((saved['examGroups'] as List).sublist(20), [0, 0, 0, 0, 0]);
      expect(saved['additionalPhase'], isTrue);
      final mainIds = main.map((q) => q['id']).toSet();
      expect(
        (saved['questionIds'] as List).sublist(20).any(mainIds.contains),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
