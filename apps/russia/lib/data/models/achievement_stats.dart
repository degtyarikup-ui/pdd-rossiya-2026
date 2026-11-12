/// Счётчики ачивок, которых нет в обычном прогрессе: лучший марафон, дни
/// учёбы утром и вечером, возвращения после перерыва и открытые знаки.
/// Хранятся на устройстве (`achievement_stats`) и только растут.
class AchievementStats {
  const AchievementStats({
    this.marathonBest = 0,
    this.earlyDays = 0,
    this.earlyLast,
    this.nightDays = 0,
    this.nightLast,
    this.comebacks = 0,
    this.signsViewed = const {},
  });

  /// Больше всего вопросов, отвеченных в одном марафоне.
  final int marathonBest;

  /// Дни, когда учёба началась с 5:00 до 9:00, и последний такой день.
  final int earlyDays;
  final String? earlyLast;

  /// Дни с учёбой с 22:00 до 4:00, и последний такой день.
  final int nightDays;
  final String? nightLast;

  /// Сколько раз человек вернулся к учёбе после перерыва в неделю и больше.
  final int comebacks;

  /// Номера знаков, открытых в справочнике.
  final Set<String> signsViewed;

  static int _int(Object? v) => v is int && v > 0 ? v : 0;

  factory AchievementStats.fromJson(Map<String, dynamic> json) =>
      AchievementStats(
        marathonBest: _int(json['marathonBest']),
        earlyDays: _int(json['earlyDays']),
        earlyLast: json['earlyLast'] as String?,
        nightDays: _int(json['nightDays']),
        nightLast: json['nightLast'] as String?,
        comebacks: _int(json['comebacks']),
        signsViewed: {
          for (final s in (json['signsViewed'] as List? ?? const []))
            if (s is String) s,
        },
      );

  Map<String, dynamic> toJson() => {
    'marathonBest': marathonBest,
    'earlyDays': earlyDays,
    'earlyLast': earlyLast,
    'nightDays': nightDays,
    'nightLast': nightLast,
    'comebacks': comebacks,
    'signsViewed': (signsViewed.toList()..sort()),
  };

  AchievementStats copyWith({
    int? marathonBest,
    int? earlyDays,
    String? earlyLast,
    int? nightDays,
    String? nightLast,
    int? comebacks,
    Set<String>? signsViewed,
  }) => AchievementStats(
    marathonBest: marathonBest ?? this.marathonBest,
    earlyDays: earlyDays ?? this.earlyDays,
    earlyLast: earlyLast ?? this.earlyLast,
    nightDays: nightDays ?? this.nightDays,
    nightLast: nightLast ?? this.nightLast,
    comebacks: comebacks ?? this.comebacks,
    signsViewed: signsViewed ?? this.signsViewed,
  );

  /// Утро — 5:00–8:59, ночь — 22:00–3:59 по часам устройства.
  static bool isEarly(DateTime t) => t.hour >= 5 && t.hour < 9;
  static bool isNight(DateTime t) => t.hour >= 22 || t.hour < 4;

  /// Перерыв, после которого новый день засчитывается как возвращение.
  static const int comebackGapDays = 7;
}
