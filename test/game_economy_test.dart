import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/core/config/game_economy.dart';

void main() {
  test('a modest streak bonus stays bounded and harder games earn more', () {
    expect(GameEconomy.signs(1), 12);
    expect(GameEconomy.signs(10000), 16);
    expect(GameEconomy.regulator(1), 24);
    expect(GameEconomy.regulator(10000), 32);
    expect(GameEconomy.city(1), 40);
    expect(GameEconomy.city(10000), 50);
    expect(GameEconomy.crossroads(10000), 50);
    expect(GameEconomy.regulator(1, hint: true), 12);
    expect(GameEconomy.regulator(10000, hint: true), 16);
    expect(GameEconomy.signs(0), GameEconomy.signs(1));
  });
  test(
    'a beginner keeps points without accuracy or minimum-answer cutoffs',
    () {
      expect(GameEconomy.rankedScore(12, correct: 1, wrong: 4), 12);
      expect(GameEconomy.rankedScore(100, correct: 4, wrong: 0), 100);
      expect(GameEconomy.rankedScore(100, correct: 5, wrong: 8), 100);
      expect(GameEconomy.rankedScore(0, correct: 0, wrong: 5), 0);
      expect(GameEconomy.rankedScore(100, correct: 0, wrong: 5), 0);
      expect(GameEconomy.rankedScore(-10, correct: 6, wrong: 0), 0);
      expect(GameEconomy.rankedScore(1000000, correct: 60000, wrong: 0), 1500);
    },
  );
  test(
    'mistakes never subtract earned points and weekly budget stays in thousands',
    () {
      expect([
        GameEconomy.signsMistake,
        GameEconomy.regulatorMistake,
        GameEconomy.crossroadsMistake,
        GameEconomy.cityMistake,
      ], everyElement(0));
      expect(GameEconomy.miniGameSeconds, 60);
      expect(GameEconomy.miniGameLives, 5);
      expect(GameEconomy.dailyRatingLimit * 7, 10500);
      final perfectCity = List.generate(
        20,
        (i) => GameEconomy.city(i + 1),
      ).reduce((a, b) => a + b);
      expect(perfectCity, 970);
      expect(perfectCity, lessThan(GameEconomy.maxRunScore));
    },
  );
}
