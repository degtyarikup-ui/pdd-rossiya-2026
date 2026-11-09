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

  test('dev rounds add to a private weekly board exactly once', () async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthService.instance;
    final service = GameLeaderboardService.instance;
    AuthService.setDebugSignInAvailableForTesting(true);
    addTearDown(() {
      auth.setSessionForTesting();
      AuthService.setDebugSignInAvailableForTesting(null);
    });

    void signIn(String id) => auth.setSessionForTesting(
      user: UserProfile(
        id: id,
        name: 'Tester',
        email: '',
        provider: AuthProviderType.google,
        createdAt: DateTime.utc(2026),
      ),
      token: 'dev_token_$id',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );

    signIn('dev_tester_1');
    expect((await service.fetch())?.me, isNull);
    final quiz = GameLeaderboardService.newRunId();
    final signs = GameLeaderboardService.newRunId();
    expect(await service.submitRun(40, runId: quiz), 1);
    expect(await service.submitRun(12, runId: signs), 1);
    await service.submitRun(40, runId: quiz);
    final board = await service.fetch();
    expect(board?.me?.score, 52);
    expect(board?.me?.runs, 2);
    signIn('dev_tester_2');
    expect((await service.fetch())?.me, isNull);
    signIn('dev_tester_1');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'dev_mock_game_rating_dev_tester_1',
      '{"week":"2000-01-03","name":"Tester","runs":{"previous":52}}',
    );
    expect((await service.fetch())?.me, isNull);
    expect(await service.hasEarnedPoints(), isTrue);
    expect(
      await service.reportProgress(
        runId: quiz,
        runScore: 60,
        delta: 20,
        newRun: false,
      ),
      isTrue,
    );
    expect((await service.fetch())?.me?.score, 20);
  });

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
