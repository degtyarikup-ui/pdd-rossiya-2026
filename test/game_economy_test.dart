import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/config/game_economy.dart';

void main() {
  test('long streaks remain bounded and harder games earn more', () {
    expect(GameEconomy.signs(10000), 14);
    expect(GameEconomy.regulator(10000), 30);
    expect(GameEconomy.crossroads(10000), 60);
    expect(GameEconomy.city(10000), 60);
    expect(GameEconomy.regulator(10000, hint: true), 15);
    expect(GameEconomy.signsMistake, greaterThan(GameEconomy.signs(10000)));
  });
  test('rating excludes short lucky runs and low accuracy', () {
    expect(GameEconomy.rankedScore(100, correct: 4, wrong: 0), 0);
    expect(GameEconomy.rankedScore(100, correct: 5, wrong: 3), 0);
    expect(GameEconomy.rankedScore(100, correct: 6, wrong: 2), 100);
    expect(GameEconomy.rankedScore(-10, correct: 6, wrong: 0), 0);
  });
}
