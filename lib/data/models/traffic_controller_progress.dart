/// Прогресс игрока в игре «Регулировщик».
library;

class TrafficControllerProgress {
  final int bestScore;
  final int maxCombo;
  final int totalSolved;
  final int trainingCount;

  const TrafficControllerProgress({
    this.bestScore = 0,
    this.maxCombo = 0,
    this.totalSolved = 0,
    this.trainingCount = 0,
  });

  TrafficControllerProgress copyWith({
    int? bestScore,
    int? maxCombo,
    int? totalSolved,
    int? trainingCount,
  }) {
    return TrafficControllerProgress(
      bestScore: bestScore ?? this.bestScore,
      maxCombo: maxCombo ?? this.maxCombo,
      totalSolved: totalSolved ?? this.totalSolved,
      trainingCount: trainingCount ?? this.trainingCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'bestScore': bestScore,
    'maxCombo': maxCombo,
    'totalSolved': totalSolved,
    'trainingCount': trainingCount,
  };

  factory TrafficControllerProgress.fromJson(Map<String, dynamic> json) {
    return TrafficControllerProgress(
      bestScore: (json['bestScore'] as num?)?.toInt() ?? 0,
      maxCombo: (json['maxCombo'] as num?)?.toInt() ?? 0,
      totalSolved: (json['totalSolved'] as num?)?.toInt() ?? 0,
      trainingCount: (json['trainingCount'] as num?)?.toInt() ?? 0,
    );
  }
}
