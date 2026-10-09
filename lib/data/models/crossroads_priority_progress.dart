import 'package:flutter/foundation.dart';

@immutable
class CrossroadsPriorityProgress {
  const CrossroadsPriorityProgress({
    this.bestScore = 0,
    this.maxCombo = 0,
    this.totalSolved = 0,
    this.trainingCount = 0,
  });

  final int bestScore;
  final int maxCombo;
  final int totalSolved;
  final int trainingCount;

  CrossroadsPriorityProgress copyWith({
    int? bestScore,
    int? maxCombo,
    int? totalSolved,
    int? trainingCount,
  }) {
    return CrossroadsPriorityProgress(
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

  factory CrossroadsPriorityProgress.fromJson(Map<String, dynamic> json) {
    return CrossroadsPriorityProgress(
      bestScore: json['bestScore'] as int? ?? 0,
      maxCombo: json['maxCombo'] as int? ?? 0,
      totalSolved: json['totalSolved'] as int? ?? 0,
      trainingCount: json['trainingCount'] as int? ?? 0,
    );
  }
}
