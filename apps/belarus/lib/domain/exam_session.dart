import 'question_bank.dart';

enum ExamOutcome { passed, failed, expired, abandoned }

/// Separate BY practice engine; never uses the Russian additional-block rules.
/// Activation is gated by reviewed questions AND reviewed exam regulations.
class ExamSession {
  static const duration = Duration(minutes: 15);
  final List<Question> questions;
  final DateTime startedAt;
  final Map<String, int> _answers = {};
  late DateTime _latestTime = startedAt;
  ExamOutcome? _outcome;

  ExamSession(List<Question> questions, {required this.startedAt})
    : questions = List.unmodifiable(questions) {
    if (questions.length != 10 ||
        questions.map((q) => q.id).toSet().length != 10 ||
        questions.where((q) => q.subject == 'pdd').length != 9) {
      throw ArgumentError('A BY ticket requires 9 PDD + 1 other question');
    }
  }

  Map<String, int> get answers => Map.unmodifiable(_answers);
  ExamOutcome? get outcome => _outcome;
  int get correctCount =>
      questions.where((q) => _answers[q.id] == q.correctIndex).length;
  DateTime get deadline => startedAt.add(duration);

  Duration remaining(DateTime now) {
    if (now.isAfter(_latestTime)) _latestTime = now;
    final remaining = deadline.difference(_latestTime);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void tick(DateTime now) {
    if (_outcome == null && remaining(now) == Duration.zero) {
      _outcome = ExamOutcome.expired;
    }
  }

  bool submit(String questionId, int answer, DateTime now) {
    tick(now);
    if (_outcome != null || _answers.containsKey(questionId)) return false;
    final question = questions.singleWhere((q) => q.id == questionId);
    if (answer < 0 || answer >= question.answers.length) {
      throw RangeError.range(answer, 0, question.answers.length - 1);
    }
    _answers[questionId] = answer;
    // Reveal the result only after all questions; no Russian extra blocks/time.
    if (_answers.length == questions.length) {
      _outcome = correctCount >= 9 ? ExamOutcome.passed : ExamOutcome.failed;
    }
    return true;
  }

  void abandon() {
    _outcome ??= ExamOutcome.abandoned;
  }
}
