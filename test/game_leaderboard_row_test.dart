import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/data/services/game_leaderboard_service.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_leaderboard_sheet.dart';

void main() {
  test('the personal leaderboard row carries a daily earning budget', () {
    final entry = GameLeaderboardEntry.fromJson({
      'rank': 3,
      'name': 'Learner',
      'score': 400,
      'runs': 2,
      'dailyEarned': 200,
      'dailyLimit': 1500,
    });
    expect(entry.dailyEarned, 200);
    expect(entry.dailyLimit, 1500);
    expect(GameLeaderboardEntry.fromJson({'score': 50}).dailyLimit, isNull);
    expect(
      GameLeaderboardService.newRunId(),
      isNot(GameLeaderboardService.newRunId()),
    );
  });

  testWidgets('scoring rules fit a narrow screen and state the daily limit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: GameLeaderboardSheet())),
    );
    await tester.pump();
    await tester.tap(find.byTooltip(appL10n.gameScoreRulesTitle));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text(appL10n.gameScoreRulesBody), findsOneWidget);
    expect(
      find.text(appL10n.gameScoreDailyLimitExplanation(1500)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'ranking keeps premium badge, rank and grouped points legible on a small screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: const Scaffold(
              body: GameLeaderboardRow(
                entry: GameLeaderboardEntry(
                  rank: 1,
                  name: 'Очень длинное имя участника рейтинга',
                  score: 1234567,
                  runs: 12,
                  isMe: false,
                  isPremium: true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.textContaining('234'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
