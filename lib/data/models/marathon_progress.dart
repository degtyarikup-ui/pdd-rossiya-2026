/// A local marathon run, independent of ordinary training and global statistics.
/// IDs preserve answers across translations and content reordering.
class MarathonProgress {
  const MarathonProgress({this.answers = const {}, this.currentQuestionId});

  final Map<String, int> answers;
  final String? currentQuestionId;

  factory MarathonProgress.fromJson(Map<String, dynamic> json) {
    final raw = json['answers'];
    if (raw is! Map || json['version'] != 1) {
      throw const FormatException('Invalid marathon progress');
    }
    return MarathonProgress(
      answers: {
        for (final entry in raw.entries)
          if (entry.key is String && entry.value is int && entry.value >= 0)
            entry.key as String: entry.value as int,
      },
      currentQuestionId: json['currentQuestionId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'answers': answers,
    'currentQuestionId': currentQuestionId,
  };

  /// Only a valid, contiguous prefix may be resumed: new/missing questions
  /// or changed answer counts must never allow skipping part of the marathon.
  List<int?> restoreChoices(List<Map<String, dynamic>> questions) {
    final choices = List<int?>.filled(questions.length, null);
    for (var i = 0; i < questions.length; i++) {
      final choice = answers[questions[i]['id']];
      final options = questions[i]['answers'] as List;
      if (choice == null || choice < 0 || choice >= options.length) break;
      choices[i] = choice;
    }
    return choices;
  }

  int resumeIndex(List<Map<String, dynamic>> questions) {
    if (questions.isEmpty) return 0;
    final choices = restoreChoices(questions);
    final firstUnanswered = choices.indexOf(null);
    final lastUnlocked = firstUnanswered < 0
        ? questions.length - 1
        : firstUnanswered;
    final saved = questions.indexWhere((q) => q['id'] == currentQuestionId);
    return saved < 0 ? lastUnlocked : saved.clamp(0, lastUnlocked);
  }
}
