import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/services/game_leaderboard_service.dart';

const _body =
    '{"ok":true,"week":"2026-W42","endsAt":"2026-10-18T21:00:00.000Z",'
    '"total":2,"top":[{"rank":1,"name":"Анна","score":500,"runs":3,'
    '"isMe":false,"isPremium":true,"avatarUrl":null}],'
    '"me":{"rank":2,"name":"Я","score":300,"runs":2,"isMe":true}}';

void main() {
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
