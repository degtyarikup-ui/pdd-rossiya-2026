import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_lobby.dart';

void main() {
  testWidgets('garage close returns to the games route', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                    body: GameLobby(
                      vehiclePaint: 'red',
                      bestScore: 0,
                      runs: const Text('3'),
                      onClose: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(GameLobby), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(GameLobby), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
