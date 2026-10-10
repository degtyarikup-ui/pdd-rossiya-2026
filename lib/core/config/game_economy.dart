/// Small, predictable rewards: learning preserves earned progress.
abstract final class GameEconomy {
  static const miniGameSeconds = 60;
  static const miniGameLives = 5;
  static const maxRunScore = 1500;
  static const dailyRatingLimit = 1500;

  static int signs(int streak) => 12 + (streak - 1).clamp(0, 4);
  static int regulator(int streak, {bool hint = false}) {
    final points = 24 + (streak - 1).clamp(0, 4) * 2;
    return hint ? points ~/ 2 : points;
  }

  static int crossroads(int streak) => 40 + (streak - 1).clamp(0, 5) * 2;
  static int city(int streak) => crossroads(streak);

  // An error already costs a life and the streak bonus. Never erase learning.
  static const signsMistake = 0;
  static const regulatorMistake = 0;
  static const crossroadsMistake = 0;
  static const cityMistake = 0;

  /// Every correct answer counts, including a beginner's first success.
  /// The shared server budget bounds weekly accumulation across all games.
  static int rankedScore(
    int score, {
    required int correct,
    required int wrong,
  }) => correct > 0 ? score.clamp(0, maxRunScore) : 0;
}
