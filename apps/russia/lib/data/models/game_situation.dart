class GameLegendItem {
  final String label;
  final String color;

  const GameLegendItem({required this.label, required this.color});

  factory GameLegendItem.fromJson(Map<String, dynamic> json) {
    return GameLegendItem(
      label: json['label'] as String? ?? '',
      color: json['color'] as String? ?? '#0574F8',
    );
  }

  Map<String, dynamic> toJson() => {'label': label, 'color': color};
}

class GameSituation {
  bool get isValid =>
      id.isNotEmpty &&
      title.isNotEmpty &&
      options.length >= 2 &&
      correctAnswerIndex >= 0 &&
      correctAnswerIndex < options.length;
  final String id;
  final String ticket;
  final String? sourceQuestionId;
  final String? country;
  final String? category;
  final String title;
  final String explanation;
  final String pddRule;
  final List<String> options;
  final int correctAnswerIndex;
  final List<GameLegendItem> legend;
  final String type;

  /// Length of the Russian source text (title and options) when the texts
  /// are translated: the time to answer follows the source, so every
  /// language gets the same time. Null: the texts above are the source.
  final int? sourceTextLength;

  const GameSituation({
    required this.id,
    required this.ticket,
    this.sourceQuestionId,
    this.country,
    this.category,
    required this.title,
    required this.explanation,
    required this.pddRule,
    required this.options,
    required this.correctAnswerIndex,
    required this.legend,
    required this.type,
    this.sourceTextLength,
  });

  factory GameSituation.fromJson(Map<String, dynamic> json) {
    return GameSituation(
      id: json['id'] as String? ?? '',
      ticket: json['ticket'] as String? ?? '',
      sourceQuestionId: json['sourceQuestionId'] as String?,
      country: json['country'] as String?,
      category: json['category'] as String?,
      title: json['title'] as String? ?? '',
      explanation: json['explanation'] as String? ?? '',
      pddRule: json['pddRule'] as String? ?? '',
      options:
          (json['options'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      correctAnswerIndex: json['correctAnswerIndex'] is int
          ? json['correctAnswerIndex'] as int
          : -1,
      legend:
          (json['legend'] as List<dynamic>?)
              ?.map(
                (e) => GameLegendItem.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList() ??
          [],
      type: json['type'] as String? ?? 'crossroad',
      sourceTextLength: (json['sourceTextLength'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'ticket': ticket,
    if (sourceQuestionId != null) 'sourceQuestionId': sourceQuestionId,
    if (country != null) 'country': country,
    if (category != null) 'category': category,
    'title': title,
    'explanation': explanation,
    'pddRule': pddRule,
    'options': options,
    'correctAnswerIndex': correctAnswerIndex,
    'legend': legend.map((l) => l.toJson()).toList(),
    'type': type,
    if (sourceTextLength != null) 'sourceTextLength': sourceTextLength,
  };
}
