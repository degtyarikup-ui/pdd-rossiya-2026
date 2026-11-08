import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/services/game_leaderboard_service.dart';

void main() {
  test('GameLeaderboardService.newRunId generates unique non-empty string', () {
    final ids = <String>{};
    for (var i = 0; i < 100; i++) {
      final id = GameLeaderboardService.newRunId();
      expect(id, isNotEmpty);
      expect(id, contains('-'));
      ids.add(id);
    }
    expect(ids.length, 100);
  });

  test('Random.secure().nextInt with safe 31-bit max', () {
    final rng = Random.secure();
    expect(rng.nextInt(0x7FFFFFFF), isNonNegative);
    expect(rng.nextInt(1 << 30), isNonNegative);
  });
}
