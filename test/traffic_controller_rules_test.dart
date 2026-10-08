import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/traffic_controller_rules.dart';

void main() {
  test('all 32 visual scenarios match the audited PDD 6.10 matrix', () {
    final rows =
        jsonDecode(
              File(
                'test/fixtures/traffic_controller_pdd_6_10.json',
              ).readAsStringSync(),
            )
            as List;
    expect(
      rows.length,
      ControllerGesture.values.length *
          ApproachDirection.values.length *
          VehicleKind.values.length,
    );
    for (final row in rows) {
      final gesture = ControllerGesture.values.byName(row['gesture']);
      final approach = ApproachDirection.values.byName(row['approach']);
      final vehicle = VehicleKind.values.byName(row['vehicle']);
      expect(
        TrafficControllerRules.allowedMoves(
          gesture: gesture,
          approach: approach,
          vehicle: vehicle,
        ).map((m) => m.name).toSet(),
        (row['moves'] as List).toSet(),
        reason: '$gesture / $approach / $vehicle',
      );
    }
  });
  group('TrafficControllerRules — Автомобиль', () {
    test('Рука вверх — движение запрещено со всех сторон', () {
      for (final approach in ApproachDirection.values) {
        final allowed = TrafficControllerRules.allowedMoves(
          gesture: ControllerGesture.armUp,
          approach: approach,
          vehicle: VehicleKind.car,
        );
        expect(allowed, {TrafficMove.none});
        expect(
          TrafficControllerRules.isMoveAllowed(
            gesture: ControllerGesture.armUp,
            approach: approach,
            vehicle: VehicleKind.car,
            move: TrafficMove.straight,
          ),
          isFalse,
        );
        expect(
          TrafficControllerRules.isMoveAllowed(
            gesture: ControllerGesture.armUp,
            approach: approach,
            vehicle: VehicleKind.car,
            move: TrafficMove.none,
          ),
          isTrue,
        );
      }
    });

    test(
      'Руки в стороны/вниз — с боков прямо и направо, с груди и спины — стоять',
      () {
        // Слева
        expect(
          TrafficControllerRules.allowedMoves(
            gesture: ControllerGesture.handsSides,
            approach: ApproachDirection.left,
            vehicle: VehicleKind.car,
          ),
          {TrafficMove.straight, TrafficMove.right},
        );

        // Справа
        expect(
          TrafficControllerRules.allowedMoves(
            gesture: ControllerGesture.handsSides,
            approach: ApproachDirection.right,
            vehicle: VehicleKind.car,
          ),
          {TrafficMove.straight, TrafficMove.right},
        );

        // С груди
        expect(
          TrafficControllerRules.allowedMoves(
            gesture: ControllerGesture.handsSides,
            approach: ApproachDirection.front,
            vehicle: VehicleKind.car,
          ),
          {TrafficMove.none},
        );

        // Со спины
        expect(
          TrafficControllerRules.allowedMoves(
            gesture: ControllerGesture.handsSides,
            approach: ApproachDirection.back,
            vehicle: VehicleKind.car,
          ),
          {TrafficMove.none},
        );
      },
    );

    test(
      'Рука вперёд — слева во всех направлениях, с груди направо, справа и со спины — стоять',
      () {
        // Слева (палка смотрит влево)
        expect(
          TrafficControllerRules.allowedMoves(
            gesture: ControllerGesture.rightArmForward,
            approach: ApproachDirection.left,
            vehicle: VehicleKind.car,
          ),
          {
            TrafficMove.straight,
            TrafficMove.right,
            TrafficMove.left,
            TrafficMove.uTurn,
          },
        );

        // С груди (палка смотрит в рот)
        expect(
          TrafficControllerRules.allowedMoves(
            gesture: ControllerGesture.rightArmForward,
            approach: ApproachDirection.front,
            vehicle: VehicleKind.car,
          ),
          {TrafficMove.right},
        );

        // Справа (палка смотрит вправо)
        expect(
          TrafficControllerRules.allowedMoves(
            gesture: ControllerGesture.rightArmForward,
            approach: ApproachDirection.right,
            vehicle: VehicleKind.car,
          ),
          {TrafficMove.none},
        );

        // Со спины
        expect(
          TrafficControllerRules.allowedMoves(
            gesture: ControllerGesture.rightArmForward,
            approach: ApproachDirection.back,
            vehicle: VehicleKind.car,
          ),
          {TrafficMove.none},
        );
      },
    );
  });

  group('TrafficControllerRules — Трамвай («из рукава в рукав»)', () {
    test('Руки в стороны/вниз — трамваю с боков ТОЛЬКО прямо', () {
      expect(
        TrafficControllerRules.allowedMoves(
          gesture: ControllerGesture.handsSides,
          approach: ApproachDirection.left,
          vehicle: VehicleKind.tram,
        ),
        {TrafficMove.straight},
      );
      expect(
        TrafficControllerRules.allowedMoves(
          gesture: ControllerGesture.handsSides,
          approach: ApproachDirection.right,
          vehicle: VehicleKind.tram,
        ),
        {TrafficMove.straight},
      );
    });

    test('Рука вперёд — слева трамваю ТОЛЬКО налево («из рукава в рукав»)', () {
      expect(
        TrafficControllerRules.allowedMoves(
          gesture: ControllerGesture.rightArmForward,
          approach: ApproachDirection.left,
          vehicle: VehicleKind.tram,
        ),
        {TrafficMove.left},
      );
    });

    test('Рука вперёд — с груди трамваю ТОЛЬКО направо', () {
      expect(
        TrafficControllerRules.allowedMoves(
          gesture: ControllerGesture.rightArmForward,
          approach: ApproachDirection.front,
          vehicle: VehicleKind.tram,
        ),
        {TrafficMove.right},
      );
    });
  });

  group('Мнемоники и стишки', () {
    test('Возвращает правильные стишки', () {
      expect(
        TrafficControllerRules.mnemonicVerse(
          gesture: ControllerGesture.armUp,
          approach: ApproachDirection.front,
          vehicle: VehicleKind.car,
        ),
        contains('Палка вверх устремлена'),
      );

      expect(
        TrafficControllerRules.mnemonicVerse(
          gesture: ControllerGesture.rightArmForward,
          approach: ApproachDirection.front,
          vehicle: VehicleKind.car,
        ),
        contains('палка смотрит в рот'),
      );

      expect(
        TrafficControllerRules.mnemonicVerse(
          gesture: ControllerGesture.rightArmForward,
          approach: ApproachDirection.right,
          vehicle: VehicleKind.car,
        ),
        contains('палка смотрит вправо'),
      );

      expect(
        TrafficControllerRules.mnemonicVerse(
          gesture: ControllerGesture.rightArmForward,
          approach: ApproachDirection.left,
          vehicle: VehicleKind.car,
        ),
        contains('палка смотрит влево'),
      );
    });
  });
}
