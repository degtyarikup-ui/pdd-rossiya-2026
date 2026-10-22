import 'package:pdd_app/data/models/sign_swiper_model.dart';

export 'package:pdd_app/data/models/sign_swiper_model.dart' show SignItem;

/// Тип вопроса викторины по дорожным знакам.
enum RoadSignQuizType {
  /// Выбор знака по его официальному названию.
  titleMatch,

  /// Выбор знака по определению / назначению из ПДД.
  meaningDefinition,

  /// Выбор знака по распространённому народному названию.
  folkNameMatch,
}

/// Вопрос викторины с 4 вариантами дорожных знаков.
class RoadSignQuizQuestion {
  final String id;
  final SignItem correctSign;

  /// Ровно 4 уникальных знака (1 правильный и 3 дистрактора).
  final List<SignItem> options;

  /// Индекс правильного ответа в списке [options] (0..3).
  final int correctAnswerIndex;

  /// Текст вопроса, предъявляемый игроку.
  final String prompt;

  /// Дословная цитата официального правила / назначения знака из ПДД РФ.
  final String officialRuleQuote;

  /// Категория / тип вопроса.
  final RoadSignQuizType type;

  const RoadSignQuizQuestion({
    required this.id,
    required this.correctSign,
    required this.options,
    required this.correctAnswerIndex,
    required this.prompt,
    required this.officialRuleQuote,
    required this.type,
  }) : assert(options.length == 4, 'Question must have exactly 4 options'),
       assert(
         correctAnswerIndex >= 0 && correctAnswerIndex < 4,
         'correctAnswerIndex must be in range 0..3',
       );
}

/// Результат ответа игрока на вопрос викторины.
class RoadSignAnswerResult {
  final RoadSignQuizQuestion question;
  final int selectedIndex;
  final bool isCorrect;

  const RoadSignAnswerResult({
    required this.question,
    required this.selectedIndex,
    required this.isCorrect,
  });

  /// Знак, выбранный игроком.
  SignItem get selectedSign => question.options[selectedIndex];

  /// Правильный знак.
  SignItem get correctSign => question.correctSign;
}

/// Сохранённый прогресс игрока в игре «Знаки».
class RoadSignsProgress {
  final int bestScore;
  final int maxCombo;
  final int totalAnswered;
  final int totalCorrect;

  const RoadSignsProgress({
    this.bestScore = 0,
    this.maxCombo = 0,
    this.totalAnswered = 0,
    this.totalCorrect = 0,
  });

  RoadSignsProgress copyWith({
    int? bestScore,
    int? maxCombo,
    int? totalAnswered,
    int? totalCorrect,
  }) {
    return RoadSignsProgress(
      bestScore: bestScore ?? this.bestScore,
      maxCombo: maxCombo ?? this.maxCombo,
      totalAnswered: totalAnswered ?? this.totalAnswered,
      totalCorrect: totalCorrect ?? this.totalCorrect,
    );
  }

  Map<String, dynamic> toJson() => {
    'bestScore': bestScore,
    'maxCombo': maxCombo,
    'totalAnswered': totalAnswered,
    'totalCorrect': totalCorrect,
  };

  factory RoadSignsProgress.fromJson(Map<String, dynamic> json) {
    return RoadSignsProgress(
      bestScore: (json['bestScore'] as num?)?.toInt() ?? 0,
      maxCombo: (json['maxCombo'] as num?)?.toInt() ?? 0,
      totalAnswered: (json['totalAnswered'] as num?)?.toInt() ?? 0,
      totalCorrect: (json['totalCorrect'] as num?)?.toInt() ?? 0,
    );
  }
}
