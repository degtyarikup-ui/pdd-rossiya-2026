/// Only these activities contribute to ticket progress and shared mistakes.
enum QuestionAnswerSource { training, exam, city }

bool isTrackedQuestionAnswer(Object? value) {
  if (value is! Map || value['isCorrect'] is! bool) return false;
  final source = value['source'];
  // Existing ticket answers predate source tracking. Keep their progress.
  return source == null ||
      QuestionAnswerSource.values.any((allowed) => allowed.name == source);
}
