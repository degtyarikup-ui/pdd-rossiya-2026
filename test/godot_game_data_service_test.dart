import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/services/game_leaderboard_service.dart';
import 'package:pdd_app/data/services/godot_game_data_service.dart';

void main() {
  test('unavailable ranking produces an explicit unavailable response', () {
    expect(GodotGameDataService.encode(null), {'available': false});
  });
  test('only public ranking display fields cross into the engine', () {
    const entry = GameLeaderboardEntry(
      rank: 3,
      name: 'Driver',
      score: 452,
      runs: 4,
      isMe: true,
      avatarUrl: 'https://example.invalid/private-avatar',
    );
    final data = GodotGameDataService.encode(
      const GameLeaderboard(
        week: 'week',
        endsAt: null,
        total: 1,
        top: [entry],
        me: entry,
        stale: true,
      ),
    );
    expect(data['available'], true);
    expect(data['stale'], true);
    expect(data['top'], [
      {'rank': 3, 'name': 'Driver', 'score': 452, 'is_me': true},
    ]);
    expect(data['me'], (data['top'] as List).single);
    expect(data.toString(), isNot(contains('private-avatar')));
  });
}
