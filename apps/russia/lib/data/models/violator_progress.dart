/// Прогресс игрока в игре «Нарушитель».
library;

class ViolatorProgress {
  final int bestScore;
  final int maxCombo;
  final int totalViolatorsCaught;
  final int totalSolved;
  final int gamesPlayed;

  const ViolatorProgress({
    this.bestScore = 0,
    this.maxCombo = 0,
    this.totalViolatorsCaught = 0,
    this.totalSolved = 0,
    this.gamesPlayed = 0,
  });

  ViolatorProgress copyWith({
    int? bestScore,
    int? maxCombo,
    int? totalViolatorsCaught,
    int? totalSolved,
    int? gamesPlayed,
  }) {
    return ViolatorProgress(
      bestScore: bestScore ?? this.bestScore,
      maxCombo: maxCombo ?? this.maxCombo,
      totalViolatorsCaught: totalViolatorsCaught ?? this.totalViolatorsCaught,
      totalSolved: totalSolved ?? this.totalSolved,
      gamesPlayed: gamesPlayed ?? this.gamesPlayed,
    );
  }

  Map<String, dynamic> toJson() => {
    'bestScore': bestScore,
    'maxCombo': maxCombo,
    'totalViolatorsCaught': totalViolatorsCaught,
    'totalSolved': totalSolved,
    'gamesPlayed': gamesPlayed,
  };

  factory ViolatorProgress.fromJson(Map<String, dynamic> json) {
    return ViolatorProgress(
      bestScore: (json['bestScore'] as num?)?.toInt() ?? 0,
      maxCombo: (json['maxCombo'] as num?)?.toInt() ?? 0,
      totalViolatorsCaught:
          (json['totalViolatorsCaught'] as num?)?.toInt() ?? 0,
      totalSolved: (json['totalSolved'] as num?)?.toInt() ?? 0,
      gamesPlayed: (json['gamesPlayed'] as num?)?.toInt() ?? 0,
    );
  }
}
