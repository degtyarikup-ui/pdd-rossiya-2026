import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/services/game_garage_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_reveal_overlay.dart';

void main() {
  testWidgets(
    'reward opens through Flutter and releases gestures after reveal',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opens = 0, chooses = 0, closes = 0, drags = 0;
      Future<void> show(bool shown) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (_) => drags++,
                    child: const SizedBox.expand(),
                  ),
                ),
                Positioned.fill(
                  child: GameRevealOverlay(
                    car: const GameCar('sedan', 'orange'),
                    shown: shown,
                    onOpen: () => opens++,
                    onChoose: () => chooses++,
                    onClose: () => closes++,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await show(false);
      await tester.tapAt(const Offset(190, 320));
      await tester.tapAt(tester.getCenter(find.text(appL10n.gameRevealTap)));
      expect(opens, 2);
      await show(true);
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(120, 320), const Offset(100, 0));
      expect(drags, greaterThan(0));
      await tester.tap(find.text(appL10n.gameRevealChoose));
      await tester.tap(find.text(appL10n.gameRevealClose));
      expect(chooses, 1);
      expect(closes, 1);
      expect(opens, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
