/// Правила сигналов регулировщика (п. 6.10 ПДД РФ).
/// Поддерживает как безрельсовые ТС (автомобили), так и трамваи
/// (принцип «трамвай едет только из рукава в рукав»).
library;

/// Жест регулировщика
enum ControllerGesture {
  /// Руки вытянуты в стороны или опущены
  handsDownOrSides,

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
    if (gesture == ControllerGesture.handsDownOrSides) {
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
      return 'Палка вверх устремлена — всем стоять велит она!';
    }

    if (gesture == ControllerGesture.rightArmForward) {
      switch (approach) {
        case ApproachDirection.front:
          return 'Если палка смотрит в рот — делай правый поворот!';
        case ApproachDirection.right:
          return 'Если палка смотрит вправо — ехать не имеешь права!';
        case ApproachDirection.left:
          if (vehicle == VehicleKind.tram) {
            return 'Трамвай едет «из рукава в рукав» — поворот только налево!';
          }
          return 'Если палка смотрит влево — поезжай как королева (в любом направлении)!';
        case ApproachDirection.back:
          return 'Грудь и спина для водителя — стена!';
      }
    }

    if (gesture == ControllerGesture.handsDownOrSides) {
      switch (approach) {
        case ApproachDirection.front:
        case ApproachDirection.back:
          return 'Грудь и спина для водителя — стена!';
        case ApproachDirection.left:
        case ApproachDirection.right:
          if (vehicle == VehicleKind.tram) {
            return 'Боком встал регулировщик — трамваю только прямо («из рукава в рукав»)!';
          }
          return 'Боком встал регулировщик — прямо и направо путь открыт!';
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
      return 'Движение запрещено (п. 6.10 ПДД)';
    }

    final movesText = allowed
        .map((m) {
          switch (m) {
            case TrafficMove.straight:
              return 'прямо';
            case TrafficMove.right:
              return 'направо';
            case TrafficMove.left:
              return 'налево';
            case TrafficMove.uTurn:
              return 'разворот';
            case TrafficMove.none:
              return 'стоять';
          }
        })
        .join(', ');

    return 'Разрешено: $movesText (п. 6.10 ПДД)';
  }
}
