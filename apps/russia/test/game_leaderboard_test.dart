import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/user_profile.dart';
import 'package:pdd_app/data/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdd_app/data/services/game_leaderboard_service.dart';

const _body =
    '{"ok":true,"week":"2026-W42","endsAt":"2026-10-18T21:00:00.000Z",'
    '"total":2,"top":[{"rank":1,"name":"Анна","score":500,"runs":3,'
    '"isMe":false,"isPremium":true,"avatarUrl":null}],'
    '"me":{"rank":2,"name":"Я","score":300,"runs":2,"isMe":true}}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'only positive points unlock the trophy, and an expired board migrates',
    () async {
      final auth = AuthService.instance;
      final service = GameLeaderboardService.instance;
      final player = UserProfile(
        id: 'player',
        name: 'Player',
        email: '',
        provider: AuthProviderType.google,
        createdAt: DateTime.utc(2026),
      );
      SharedPreferences.setMockInitialValues({});
      auth.setSessionForTesting(user: player);
      addTearDown(() => auth.setSessionForTesting());
      expect(await service.hasEarnedPoints(), isFalse);
      await service.submitRun(0, runId: 'zero');
      expect(await service.hasEarnedPoints(), isFalse);

      final prefs = await SharedPreferences.getInstance();
      final oldBoard = Map<String, dynamic>.from(jsonDecode(_body) as Map)
        ..['endsAt'] = DateTime.utc(2000).toIso8601String();
      await prefs.setString(
        'game_board_cache_v1',
        jsonEncode({
          'userId': player.id,
          'body': jsonEncode(oldBoard),
          'savedAt': 0,
        }),
      );
      expect(await service.lastKnown(), isNull);
      expect(await service.hasEarnedPoints(), isTrue);
      await prefs.remove('game_board_cache_v1');
      expect(await service.hasEarnedPoints(), isTrue);
      auth.setSessionForTesting();
      expect(await service.hasEarnedPoints(), isFalse);
    },
  );

  test('ответ сервера разбирается: неделя, место и очки игрока', () {
    final board = GameLeaderboard.parse(_body);

    expect(board, isNotNull);
    expect(board!.week, '2026-W42');
    expect(board.top.single.name, 'Анна');
    expect(board.me?.rank, 2);
    expect(board.stale, isFalse);
  });

  test('не объект и не JSON не принимаются за рейтинг', () {
    expect(GameLeaderboard.parse('[]'), isNull);
    expect(() => GameLeaderboard.parse('не json'), throwsFormatException);
  });

  test('сохранённый рейтинг помечается и уходит после конца недели', () {
    final board = GameLeaderboard.parse(_body, stale: true)!;

    expect(board.stale, isTrue);
    expect(board.isCurrentAt(DateTime.utc(2026, 10, 18, 20)), isTrue);
    expect(board.isCurrentAt(DateTime.utc(2026, 10, 18, 22)), isFalse);
  });
}
