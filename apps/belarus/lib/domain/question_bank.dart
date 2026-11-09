import 'dart:math';

class Question {
  final String id;
  final String text;
  final List<String> answers;
  final int correctIndex;
  final String subject;
  final String sourceId;
  final String explanation;
  final List<String> imageAssets;

  Question.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      text = json['text'] as String,
      answers = List.unmodifiable((json['answers'] as List).cast<String>()),
      correctIndex = json['correctIndex'] as int,
      subject = json['subject'] as String,
      sourceId = json['sourceId'] as String,
      explanation = json['explanation'] as String,
      imageAssets = List.unmodifiable(
        (json['imageAssets'] as List? ?? []).cast<String>(),
      ) {
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
    if (json['image'] != null ||
        imageAssets.any(
          (path) => !RegExp(
            r'^assets/countries/by/preview_[a-f0-9]{64}\.(jpg|jpeg|png|webp|gif)$',
          ).hasMatch(path),
        )) {
      throw const FormatException('Invalid Belarus image asset');
    }
  }
}

class QuestionBank {
  final String revision;
  final bool reviewed;
  final bool previewOnly;
  final bool examRulesReviewed;
  final List<Question> questions;

  QuestionBank.fromJson(Map<String, dynamic> json)
    : revision = json['revision'] as String,
      reviewed = json['reviewStatus'] == 'approved',
      previewOnly = json['previewOnly'] == true,
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
    if (!previewOnly && questions.any((q) => q.imageAssets.isNotEmpty)) {
      throw const FormatException(
        'Image questions currently require preview mode',
      );
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
      !previewOnly &&
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
