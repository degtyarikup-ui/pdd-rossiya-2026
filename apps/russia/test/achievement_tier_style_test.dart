import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/achievement.dart';
import 'package:pdd_app/presentation/screens/profile/widgets/achievement_tier_style.dart';

void main() {
  test('уровень выбирает металл, выход за 1..4 прижимается к краям', () {
    expect(TierMetal.of(0), same(TierMetal.bronze));
    expect(TierMetal.of(1), same(TierMetal.bronze));
    expect(TierMetal.of(2), same(TierMetal.silver));
    expect(TierMetal.of(3), same(TierMetal.gold));
    expect(TierMetal.of(4), same(TierMetal.platinum));
    expect(TierMetal.of(9), same(TierMetal.platinum));
    // Высший уровень — акцентный синий приложения на экране награды.
    expect(TierMetal.platinum.award, const Color(0xFF0574F8));
  });

  test('центр лучей задан для каждой ачивки и лежит внутри значка', () {
    for (final id in AchievementId.values) {
      final f = achievementFocus(id);
      expect(f.dx, inInclusiveRange(.3, .7), reason: id.name);
      expect(f.dy, inInclusiveRange(.2, .6), reason: id.name);
    }
  });

  testWidgets('полоска: полученные сегменты полные, следующий по прогрессу', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            child: TierLevelBar(
              level: 2,
              total: 4,
              progress: .5,
              fill: Colors.orange,
              track: Colors.grey,
            ),
          ),
        ),
      ),
    );
    final values = tester
        .widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        )
        .map((p) => p.value)
        .toList();
    expect(values, [1, 1, .5, 0]);
  });
}
