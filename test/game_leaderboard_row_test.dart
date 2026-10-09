import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/services/game_leaderboard_service.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_leaderboard_sheet.dart';

void main() {
  testWidgets('ranking keeps premium badge, rank and grouped points legible on a small screen', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: MediaQuery(
      data: const MediaQueryData(size: Size(320,640), textScaler: TextScaler.linear(2)),
      child: const Scaffold(body: GameLeaderboardRow(entry: GameLeaderboardEntry(
        rank: 1, name: 'Очень длинное имя участника рейтинга', score: 1234567,
        runs: 12, isMe: false, isPremium: true,
      ))),
    )));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.textContaining('234'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
