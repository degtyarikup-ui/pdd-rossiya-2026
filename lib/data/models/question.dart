class Question {
  final String id;
  final String question;
  final List<Answer> answers;
  final String? comment;
  final List<String> pddPoints;
  final String? image;
  final List<String> topic;
  final int ticketNumber;

  Question({
    required this.id,
    required this.question,
    required this.answers,
    this.comment,
    this.pddPoints = const [],
    this.image,
    this.topic = const [],
    this.ticketNumber = 0,
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      id: json['id'] as String? ?? '',
      question: json['question'] as String? ?? '',
      answers: (json['answers'] as List<dynamic>?)
              ?.map((a) => Answer.fromJson(a as Map<String, dynamic>))
              .toList() ??
          [],
      comment: json['comment'] as String?,
      pddPoints: (json['pddPoints'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      image: json['image'] as String?,
      topic: (json['topic'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      ticketNumber: json['ticketNumber'] as int? ?? 0,
    );
  }

  int get correctAnswerIndex {
    for (int i = 0; i < answers.length; i++) {
      if (answers[i].isCorrect) return i;
    }
    return 0;
  }

  bool hasImage() => image != null && image!.isNotEmpty && image != 'no_image';
}

class Answer {
  final String text;
  final bool isCorrect;

  const Answer({
    required this.text,
    required this.isCorrect,
  });

  factory Answer.fromJson(Map<String, dynamic> json) {
    return Answer(
      text: json['text'] as String? ?? json['answer_text'] as String? ?? '',
      isCorrect: json['correct'] as bool? ?? json['is_correct'] as bool? ?? false,
    );
  }
}
