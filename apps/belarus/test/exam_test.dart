import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_belarus/domain/question_bank.dart';
import 'package:pdd_belarus/domain/exam_session.dart';
import 'fixtures.dart';

void main() {
  final start = DateTime.utc(2026, 11, 9);
  List<Question> ticket() =>
      QuestionBank.fromJson(bankJson()).newExam(random: Random(42));
  test('selection is unique, 9 PDD + 1 other, and does not mutate bank', () {
    final bank = QuestionBank.fromJson(bankJson());
    final before = bank.questions.map((q) => q.id).toList();
    for (var i = 0; i < 30; i++) {
      final selected = bank.newExam(random: Random(i));
      expect(selected.length, 10);
      expect(selected.map((q) => q.id).toSet().length, 10);
      expect(selected.where((q) => q.subject == 'pdd').length, 9);
    }
    expect(bank.questions.map((q) => q.id), before);
  });
  for (final errors in [0, 1, 2]) {
    test('$errors errors: complete all ten with no additional blocks', () {
      final session = ExamSession(ticket(), startedAt: start);
      for (var i = 0; i < 10; i++) {
        expect(
          session.submit(
            session.questions[i].id,
            i < errors ? 1 : 0,
            start.add(Duration(seconds: i)),
          ),
          isTrue,
        );
        if (i < 9) expect(session.outcome, isNull);
      }
      expect(
        session.outcome,
        errors < 2 ? ExamOutcome.passed : ExamOutcome.failed,
      );
      expect(session.deadline, start.add(const Duration(minutes: 15)));
      expect(session.questions.length, 10);
    });
  }
  test(
    'background timeout includes unanswered question and refuses late answer',
    () {
      final session = ExamSession(ticket(), startedAt: start);
      for (final q in session.questions.take(9)) {
        session.submit(q.id, 0, start);
      }
      expect(
        session.submit(
          session.questions.last.id,
          0,
          start.add(const Duration(minutes: 15)),
        ),
        isFalse,
      );
      expect(session.outcome, ExamOutcome.expired);
      expect(session.correctCount, 9);
    },
  );
  test('deadline boundary, clock rollback, immutable submitted answers', () {
    final session = ExamSession(ticket(), startedAt: start);
    final id = session.questions.first.id;
    expect(session.submit(id, 1, start), isTrue);
    expect(session.submit(id, 0, start), isFalse);
    expect(() => session.answers[id] = 0, throwsUnsupportedError);
    expect(
      session.remaining(start.add(const Duration(minutes: 10))),
      const Duration(minutes: 5),
    );
    expect(session.remaining(start), const Duration(minutes: 5));
    session.tick(start.add(const Duration(minutes: 15)));
    expect(session.outcome, ExamOutcome.expired);
  });
  test('abandoned session stays terminal', () {
    final session = ExamSession(ticket(), startedAt: start)..abandon();
    expect(session.submit(session.questions.first.id, 0, start), isFalse);
    session.tick(start.add(const Duration(days: 1)));
    expect(session.outcome, ExamOutcome.abandoned);
  });
  test('invalid ticket rejected', () {
    expect(
      () => ExamSession(ticket().take(9).toList(), startedAt: start),
      throwsArgumentError,
    );
  });
  test('content and regulation reviews independently gate starting', () {
    for (final key in ['reviewStatus', 'examRulesReviewed']) {
      final json = bankJson();
      json[key] = key == 'reviewStatus' ? 'pending' : false;
      final bank = QuestionBank.fromJson(json);
      expect(bank.canStartExam, isFalse);
      expect(bank.newExam, throwsStateError);
    }
    expect(QuestionBank.fromJson(bankJson(other: 0)).canStartExam, isFalse);
  });
  test(
    'foreign bank, invalid answers, missing sources and duplicates rejected',
    () {
      final badBanks = <Map<String, dynamic>>[];
      badBanks.add(bankJson()..['country'] = 'ru');
      var data = bankJson();
      (data['questions'] as List).first['correctIndex'] = 5;
      badBanks.add(data);
      data = bankJson();
      (data['questions'] as List)[1]['id'] = 'by:test:0';
      badBanks.add(data);
      data = bankJson();
      data['sources'] = [];
      badBanks.add(data);
      data = bankJson();
      (data['sources'] as List).first['reviewStatus'] = 'pending';
      badBanks.add(data);
      for (final data in badBanks) {
        expect(() => QuestionBank.fromJson(data), throwsFormatException);
      }
    },
  );
}
