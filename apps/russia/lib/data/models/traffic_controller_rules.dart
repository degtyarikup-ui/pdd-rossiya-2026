/// Правила сигналов регулировщика (п. 6.10 ПДД РФ).
/// Поддерживает как безрельсовые ТС (автомобили), так и трамваи
/// (принцип «трамвай едет только из рукава в рукав»).
library;

import 'package:pdd_app/l10n/l10n.dart';

/// Жест регулировщика
enum ControllerGesture {
  /// Руки вытянуты в стороны
  handsSides,

  /// Руки опущены (то же правило, отдельная визуальная поза).
  handsDown,

  /// Правая рука вытянута вперёд
  rightArmForward,

  /// Рука поднята вверх
  armUp,
}

/// Ракурс приближения ТС к регулировщику
enum ApproachDirection {
  /// Со стороны груди (регулировщик стоит лицом)
  front,

  /// Со стороны спины
  back,

  /// Со стороны левого бока
  left,

  /// Со стороны правого бока
  right,
}

/// Тип транспортного средства
enum VehicleKind {
  /// Безрельсовое ТС (легковой автомобиль)
  car,

  /// Трамвай
  tram,
}

/// Направление манёвра
enum TrafficMove {
  straight,
  right,
  left,
  uTurn,
  none, // Стоять
}

class TrafficControllerRules {
  TrafficControllerRules._();

  /// Получить разрешённые направления движения для ТС
  static Set<TrafficMove> allowedMoves({
    required ControllerGesture gesture,
    required ApproachDirection approach,
    required VehicleKind vehicle,
  }) {
    // 1. Рука поднята вверх — всем стоять
    if (gesture == ControllerGesture.armUp) {
      return {TrafficMove.none};
    }

    // 2. Руки вытянуты в стороны или опущены
    if (gesture == ControllerGesture.handsSides ||
        gesture == ControllerGesture.handsDown) {
      switch (approach) {
        case ApproachDirection.left:
        case ApproachDirection.right:
          if (vehicle == VehicleKind.tram) {
            return {TrafficMove.straight};
          } else {
            return {TrafficMove.straight, TrafficMove.right};
          }
        case ApproachDirection.front:
        case ApproachDirection.back:
          return {TrafficMove.none};
      }
    }

    // 3. Правая рука вытянута вперёд
    if (gesture == ControllerGesture.rightArmForward) {
      switch (approach) {
        case ApproachDirection.left:
          if (vehicle == VehicleKind.tram) {
            return {TrafficMove.left}; // из левого рукава в правый
          } else {
            return {
              TrafficMove.straight,
              TrafficMove.right,
              TrafficMove.left,
              TrafficMove.uTurn,
            };
          }
        case ApproachDirection.front:
          return {TrafficMove.right}; // палка в рот — делай правый поворот
        case ApproachDirection.right:
        case ApproachDirection.back:
          return {TrafficMove.none}; // палка вправо / спина — стена
      }
    }

    return {TrafficMove.none};
  }

  /// Проверить, разрешён ли конкретный манёвр
  static bool isMoveAllowed({
    required ControllerGesture gesture,
    required ApproachDirection approach,
    required VehicleKind vehicle,
    required TrafficMove move,
  }) {
    final allowed = allowedMoves(
      gesture: gesture,
      approach: approach,
      vehicle: vehicle,
    );
    if (move == TrafficMove.none) {
      return allowed.contains(TrafficMove.none);
    }
    return allowed.contains(move);
  }

  /// Народный стишок-мнемоника для текущей ситуации
  static String mnemonicVerse({
    required ControllerGesture gesture,
    required ApproachDirection approach,
    required VehicleKind vehicle,
  }) {
    if (gesture == ControllerGesture.armUp) {
      return appL10n.gameTrafficHintArmUp;
    }

    if (gesture == ControllerGesture.rightArmForward) {
      switch (approach) {
        case ApproachDirection.front:
          return appL10n.gameTrafficHintForwardFront;
        case ApproachDirection.right:
          return appL10n.gameTrafficHintForwardRight;
        case ApproachDirection.left:
          if (vehicle == VehicleKind.tram) {
            return appL10n.gameTrafficHintTramLeft;
          }
          return appL10n.gameTrafficHintForwardLeft;
        case ApproachDirection.back:
          return appL10n.gameTrafficHintBack;
      }
    }

    if (gesture == ControllerGesture.handsSides ||
        gesture == ControllerGesture.handsDown) {
      switch (approach) {
        case ApproachDirection.front:
          return appL10n.gameTrafficHintWall;
        case ApproachDirection.back:
          return appL10n.gameTrafficHintBack;
        case ApproachDirection.left:
        case ApproachDirection.right:
          if (vehicle == VehicleKind.tram) {
            return appL10n.gameTrafficHintTramStraight;
          }
          return appL10n.gameTrafficHintSide;
      }
    }

    return '';
  }

  /// Краткое официальное правило п. 6.10 ПДД
  static String officialRuleDescription({
    required ControllerGesture gesture,
    required ApproachDirection approach,
    required VehicleKind vehicle,
  }) {
    final allowed = allowedMoves(
      gesture: gesture,
      approach: approach,
      vehicle: vehicle,
    );

    if (allowed.contains(TrafficMove.none)) {
      return appL10n.gameTrafficHintForbidden;
    }

    final movesText = allowed
        .map((m) {
          switch (m) {
            case TrafficMove.straight:
              return appL10n.gameActionStraight.toLowerCase();
            case TrafficMove.right:
              return appL10n.gameActionRight.toLowerCase();
            case TrafficMove.left:
              return appL10n.gameActionLeft.toLowerCase();
            case TrafficMove.uTurn:
              return appL10n.gameActionUTurn.toLowerCase();
            case TrafficMove.none:
              return appL10n.gameActionStand.toLowerCase();
          }
        })
        .join(', ');

    return appL10n.gameTrafficHintAllowed(movesText);
  }
}
