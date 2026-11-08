import 'dart:math';

class Question {
  final String id;
  final String text;
  final List<String> answers;
  final int correctIndex;
  final String subject;
  final String sourceId;
  final String explanation;

  Question.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      text = json['text'] as String,
      answers = List.unmodifiable((json['answers'] as List).cast<String>()),
      correctIndex = json['correctIndex'] as int,
      subject = json['subject'] as String,
      sourceId = json['sourceId'] as String,
      explanation = json['explanation'] as String {
    if (!id.startsWith('by:') ||
        text.trim().isEmpty ||
        answers.length < 2 ||
        answers.length > 5 ||
        answers.any((a) => a.trim().isEmpty) ||
        answers.map((a) => a.trim()).toSet().length != answers.length ||
        correctIndex < 0 ||
        correctIndex >= answers.length ||
        !['pdd', 'other'].contains(subject) ||
        explanation.trim().isEmpty) {
      throw const FormatException('Invalid Belarus question');
    }
    // Images need an explicitly reviewed asset pipeline before being supported.
    if (json['image'] != null) throw const FormatException('Unsupported image');
  }
}

class QuestionBank {
  final String revision;
  final bool reviewed;
  final bool examRulesReviewed;
  final List<Question> questions;

  QuestionBank.fromJson(Map<String, dynamic> json)
    : revision = json['revision'] as String,
      reviewed = json['reviewStatus'] == 'approved',
      examRulesReviewed = json['examRulesReviewed'] == true,
      questions = List.unmodifiable(
        (json['questions'] as List).map(
          (q) => Question.fromJson(Map<String, dynamic>.from(q as Map)),
        ),
      ) {
    if (json['schemaVersion'] != 1 ||
        json['country'] != 'by' ||
        revision.isEmpty ||
        !['pending', 'approved'].contains(json['reviewStatus'])) {
      throw const FormatException('Invalid Belarus catalog');
    }
    final sourceIds = <String>{};
    for (final source in json['sources'] as List) {
      final url = Uri.tryParse(source['url'] as String);
      final id = source['id'] as String;
      if (id.isEmpty ||
          !sourceIds.add(id) ||
          url?.scheme != 'https' ||
          url!.host.isEmpty ||
          (source['license'] as String).trim().isEmpty ||
          (source['revision'] as String).trim().isEmpty ||
          DateTime.tryParse(source['checkedAt'] as String) == null ||
          (reviewed && source['reviewStatus'] != 'approved')) {
        throw const FormatException('Unreviewed or invalid source');
      }
    }
    if (questions.map((q) => q.id).toSet().length != questions.length ||
        questions.any((q) => !sourceIds.contains(q.sourceId))) {
      throw const FormatException('Duplicate question or missing source');
    }
  }

  bool get canStartExam =>
      reviewed &&
      examRulesReviewed &&
      questions.where((q) => q.subject == 'pdd').length >= 9 &&
      questions.any((q) => q.subject == 'other');

  List<Question> newExam({Random? random}) {
    if (!canStartExam) throw StateError('Belarus content is not ready');
    final rng = random ?? Random();
    final pdd = questions.where((q) => q.subject == 'pdd').toList()
      ..shuffle(rng);
    final other = questions.where((q) => q.subject == 'other').toList()
      ..shuffle(rng);
    return List.unmodifiable([...pdd.take(9), other.first]..shuffle(rng));
  }
}
