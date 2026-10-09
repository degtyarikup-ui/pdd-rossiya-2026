/// Comparable weekly rewards: knowledge earns points, distance does not.
abstract final class GameEconomy {
  static int signs(int streak) => 8 + (streak - 1).clamp(0, 3) * 2;
  static int regulator(int streak, {bool hint = false}) {
    final points = 18 + (streak - 1).clamp(0, 4) * 3;
    return hint ? points ~/ 2 : points;
  }

  static int crossroads(int streak) => 40 + (streak - 1).clamp(0, 4) * 5;
  static int city(int streak) => crossroads(streak);
  static const signsMistake = 24;
  static const regulatorMistake = 40;
  static const crossroadsMistake = 80;
  static const cityMistake = 65;

  /// Short lucky streaks and random swipes do not count towards the rating.
  static int rankedScore(
    int score, {
    required int correct,
    required int wrong,
  }) {
    return correct >= 5 && correct * 4 >= (correct + wrong) * 3
        ? score.clamp(0, 1000000)
        : 0;
  }
}
