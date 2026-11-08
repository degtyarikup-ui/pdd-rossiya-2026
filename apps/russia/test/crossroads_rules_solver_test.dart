import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/crossroads_priority_model.dart';

/// Независимая проверка очередности в игре «Перекресток».
///
/// Решатель сам считает порядок по ПДД и сверяет его с тем, что записано
/// в сценарии. Траектории — те же кривые, что рисует игра
/// (assets/game/crossroads.js: placeActorAtStart, generateTrajectory),
/// поэтому «помеха» здесь — это реальное пересечение путей на сцене.
///
/// Правила:
/// - п. 3.2: спецсигналы — раньше всех;
/// - п. 13.9: второстепенная уступает главной;
/// - п. 13.10/13.11: в равных условиях — трамвай раньше, иначе помеха справа;
/// - п. 13.12: при повороте налево/развороте — уступить встречным.
///
/// На каждом шаге правильный ответ должен быть ровно один: иначе игрок
/// получает «ДТП» за допустимый по правилам выбор.
void main() {
  const laneOffset = 3.4, halfRoad = 6.8, exitD = halfRoad + 32;

  ({double x, double z}) start(CrossroadsActor a) {
    if (a.type == CrossroadsVehicleType.pedestrian) {
      const crossingDist = halfRoad + 3.8;
      const curbDist = halfRoad + 1.6;
      return switch (a.side) {
        CrossroadsSide.south => (x: -curbDist, z: crossingDist),
        CrossroadsSide.north => (x: curbDist, z: -crossingDist),
        CrossroadsSide.east => (x: crossingDist, z: curbDist),
        CrossroadsSide.west => (x: -crossingDist, z: -curbDist),
      };
    }
    final tram = a.type == CrossroadsVehicleType.tram;
    final stop = tram
        ? 17.0
        : a.type == CrossroadsVehicleType.bus
        ? 17.2
        : a.type == CrossroadsVehicleType.truck
        ? 15.8
        : 14.8;
    final l = tram ? 0.0 : laneOffset;
    return switch (a.side) {
      CrossroadsSide.south => (x: l, z: stop),
      CrossroadsSide.north => (x: -l, z: -stop),
      CrossroadsSide.east => (x: stop, z: -l),
      CrossroadsSide.west => (x: -stop, z: l),
    };
  }

  List<({double x, double z})> path(CrossroadsActor a) {
    final s = start(a);
    final l = a.type == CrossroadsVehicleType.tram ? 0.0 : laneOffset;
    final side = a.side;
    ({double x, double z}) p(double x, double z) => (x: x, z: z);
    List<({double x, double z})> quad(
      ({double x, double z}) m,
      ({double x, double z}) e,
    ) => [
      for (var i = 0; i <= 60; i++)
        () {
          final t = i / 60, u = 1 - t;
          return p(
            u * u * s.x + 2 * u * t * m.x + t * t * e.x,
            u * u * s.z + 2 * u * t * m.z + t * t * e.z,
          );
        }(),
    ];
    switch (a.maneuver) {
      case CrossroadsManeuver.cross:
        const crossingDist = halfRoad + 3.8;
        const curbDist = halfRoad + 1.6;
        final end = switch (side) {
          CrossroadsSide.south => p(curbDist, crossingDist),
          CrossroadsSide.north => p(-curbDist, -crossingDist),
          CrossroadsSide.east => p(crossingDist, -curbDist),
          CrossroadsSide.west => p(-crossingDist, curbDist),
        };
        return [
          for (var i = 0; i <= 60; i++)
            () {
              final t = i / 60, u = 1 - t;
              return p(u * s.x + t * end.x, u * s.z + t * end.z);
            }(),
        ];
      case CrossroadsManeuver.straight:
        final e = switch (side) {
          CrossroadsSide.south => p(l, -exitD),
          CrossroadsSide.north => p(-l, exitD),
          CrossroadsSide.east => p(-exitD, -l),
          CrossroadsSide.west => p(exitD, l),
        };
        return quad(p((s.x + e.x) / 2, (s.z + e.z) / 2), e);
      case CrossroadsManeuver.right:
        return switch (side) {
          CrossroadsSide.south => quad(p(l + 2, l + 2), p(exitD, l)),
          CrossroadsSide.north => quad(p(-l - 2, -l - 2), p(-exitD, -l)),
          CrossroadsSide.east => quad(p(l + 2, -l - 2), p(l, -exitD)),
          CrossroadsSide.west => quad(p(-l - 2, l + 2), p(-l, exitD)),
        };
      case CrossroadsManeuver.left:
        return switch (side) {
          CrossroadsSide.south => quad(p(l * .6, -l * .6), p(-exitD, -l)),
          CrossroadsSide.north => quad(p(-l * .6, l * .6), p(exitD, l)),
          CrossroadsSide.east => quad(p(-l * .6, -l * .6), p(-l, exitD)),
          CrossroadsSide.west => quad(p(l * .6, l * .6), p(l, -exitD)),
        };
      case CrossroadsManeuver.uTurn:
        final (c1, c2, e) = switch (side) {
          CrossroadsSide.south => (p(l, -2.5), p(-l, -2.5), p(-l, exitD)),
          CrossroadsSide.north => (p(-l, 2.5), p(l, 2.5), p(l, -exitD)),
          CrossroadsSide.east => (p(-2.5, -l), p(-2.5, l), p(exitD, l)),
          CrossroadsSide.west => (p(2.5, l), p(2.5, -l), p(-exitD, -l)),
        };
        return [
          for (var i = 0; i <= 60; i++)
            () {
              final t = i / 60, u = 1 - t;
              double c(double a0, double a1, double a2, double a3) =>
                  u * u * u * a0 +
                  3 * u * u * t * a1 +
                  3 * u * t * t * a2 +
                  t * t * t * a3;
              return p(c(s.x, c1.x, c2.x, e.x), c(s.z, c1.z, c2.z, e.z));
            }(),
        ];
    }
  }

  bool conflict(CrossroadsActor a, CrossroadsActor b) {
    final pa = path(a), pb = path(b);
    for (final x in pa) {
      for (final y in pb) {
        if (math.sqrt(math.pow(x.x - y.x, 2) + math.pow(x.z - y.z, 2)) < 2.0) {
          return true;
        }
      }
    }
    return false;
  }

  const rightOf = {
    CrossroadsSide.south: CrossroadsSide.east,
    CrossroadsSide.east: CrossroadsSide.north,
    CrossroadsSide.north: CrossroadsSide.west,
    CrossroadsSide.west: CrossroadsSide.south,
  };
  const opposite = {
    CrossroadsSide.south: CrossroadsSide.north,
    CrossroadsSide.north: CrossroadsSide.south,
    CrossroadsSide.east: CrossroadsSide.west,
    CrossroadsSide.west: CrossroadsSide.east,
  };

  /// 2 — главная, 1 — равнозначная, 0 — второстепенная.
  int rank(CrossroadsScenario s, CrossroadsSide side) {
    if (s.isEqualCrossroad) return 1;
    final codes = s.signs.where((x) => x.side == side).map((x) => x.code);
    if (codes.any((c) => c == '2.4' || c == '2.5')) return 0;
    if (codes.any((c) => c == '2.1' || c.startsWith('2.3'))) return 2;
    return 1;
  }

  bool mustYield(CrossroadsScenario s, CrossroadsActor a, CrossroadsActor b) {
    bool siren(CrossroadsActor x) => x.hasSiren;
    if (siren(b) && !siren(a)) return true;
    if (siren(a) && !siren(b)) return false;
    if (!conflict(a, b)) return false;

    if (s.isRegulated) {
      final tla = s.trafficLights?.where((x) => x.side == a.side).firstOrNull;
      final tlb = s.trafficLights?.where((x) => x.side == b.side).firstOrNull;
      final aMainGreen = tla?.state == 'green';
      final bMainGreen = tlb?.state == 'green';
      final aArrowRed = tla?.state == 'red' && (tla?.arrowActive ?? false);
      final bArrowRed = tlb?.state == 'red' && (tlb?.arrowActive ?? false);

      // Пешеход на регулируемом перекрестке уступает машинам на основной зеленый прямо
      if (a.type == CrossroadsVehicleType.pedestrian) {
        if (bMainGreen && b.maneuver == CrossroadsManeuver.straight) {
          return true;
        }
        return false;
      }
      if (b.type == CrossroadsVehicleType.pedestrian) {
        if (aMainGreen && a.maneuver == CrossroadsManeuver.straight) {
          return false;
        }
        return true;
      }

      // Движение по стрелке при красном сигнале уступает основному зелёному (п. 13.5, 13.6).
      // Даже трамвай на стрелку с красным обязан уступить автомобилю на основной зелёный (п. 13.6).
      if (aArrowRed && bMainGreen) return true;
      if (bArrowRed && aMainGreen) return false;

      // Трамвай на равных сигналах имеет преимущество
      bool tram(CrossroadsActor x) => x.type == CrossroadsVehicleType.tram;
      if (tram(b) && !tram(a)) return true;
      if (tram(a) && !tram(b)) return false;

      // Поворот налево на зелёный уступает встречным прямо/направо (п. 13.4)
      final turningAcross =
          a.maneuver == CrossroadsManeuver.left ||
          a.maneuver == CrossroadsManeuver.uTurn;
      final bThrough =
          b.maneuver == CrossroadsManeuver.straight ||
          b.maneuver == CrossroadsManeuver.right;
      if (turningAcross && bThrough && b.side == opposite[a.side]) return true;
      final bTurningAcross =
          b.maneuver == CrossroadsManeuver.left ||
          b.maneuver == CrossroadsManeuver.uTurn;
      final aThrough =
          a.maneuver == CrossroadsManeuver.straight ||
          a.maneuver == CrossroadsManeuver.right;
      if (bTurningAcross && aThrough && a.side == opposite[b.side]) {
        return false;
      }
      return rightOf[a.side] == b.side;
    }

    // Нерегулируемый перекресток: пешеход на переходе (п. 13.1, 14.1)
    if (a.type == CrossroadsVehicleType.pedestrian) return false;
    if (b.type == CrossroadsVehicleType.pedestrian) return true;

    final ra = rank(s, a.side), rb = rank(s, b.side);
    if (ra != rb) return rb > ra;
    bool tram(CrossroadsActor x) => x.type == CrossroadsVehicleType.tram;
    if (tram(b) && !tram(a)) return true;
    if (tram(a) && !tram(b)) return false;
    final turningAcross =
        a.maneuver == CrossroadsManeuver.left ||
        a.maneuver == CrossroadsManeuver.uTurn;
    final bThrough =
        b.maneuver == CrossroadsManeuver.straight ||
        b.maneuver == CrossroadsManeuver.right;
    if (turningAcross && bThrough && b.side == opposite[a.side]) return true;
    final bTurningAcross =
        b.maneuver == CrossroadsManeuver.left ||
        b.maneuver == CrossroadsManeuver.uTurn;
    final aThrough =
        a.maneuver == CrossroadsManeuver.straight ||
        a.maneuver == CrossroadsManeuver.right;
    if (bTurningAcross && aThrough && a.side == opposite[b.side]) return false;
    return rightOf[a.side] == b.side;
  }

  for (final scenario in CrossroadsScenariosLibrary.allScenarios) {
    test(
      '${scenario.id}: порядок по ПДД и единственный ответ на каждом шаге',
      () {
        final remaining = List.of(scenario.actors);
        final solved = <String>[];
        while (remaining.isNotEmpty) {
          final free = remaining
              .where(
                (a) =>
                    !remaining.any((b) => b != a && mustYield(scenario, a, b)),
              )
              .toList();
          expect(
            free.length,
            1,
            reason:
                'шаг ${solved.length + 1}: могут ехать ${free.map((a) => a.id)}',
          );
          solved.add(free.single.id);
          remaining.remove(free.single);
        }
        expect(solved, scenario.orderedActors.map((a) => a.id).toList());
      },
    );

    test(
      '${scenario.id}: машины не стоят на закрытой стороне и не едут туда',
      () {
        final closed = scenario.closedSide;
        if (closed == null) return;
        for (final a in scenario.actors) {
          expect(a.side, isNot(closed));
          final exit = switch (a.maneuver) {
            CrossroadsManeuver.straight => opposite[a.side],
            CrossroadsManeuver.right => rightOf[a.side],
            CrossroadsManeuver.left => opposite[rightOf[a.side]],
            CrossroadsManeuver.uTurn => a.side,
            CrossroadsManeuver.cross => a.side,
          };
          expect(exit, isNot(closed), reason: a.id);
        }
      },
    );
  }
}
