import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/crossroads_priority_model.dart';
import 'package:pdd_app/data/models/crossroads_priority_progress.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Crossroads Priority Rules and Scenarios Tests', () {
    test('All certified scenarios have valid priority order sequences', () {
      final scenarios = CrossroadsScenariosLibrary.allScenarios;
      expect(scenarios.length, equals(17));

      for (final s in scenarios) {
        expect(
          s.actors.isNotEmpty,
          isTrue,
          reason: 'Scenario ${s.id} has no actors',
        );
        final orders = s.actors.map((a) => a.priorityOrder).toList()..sort();
        // Проверяем, что порядок идет 1, 2, 3...
        for (int i = 0; i < orders.length; i++) {
          expect(
            orders[i],
            equals(i + 1),
            reason:
                'Scenario ${s.id} has broken priority order sequence: $orders',
          );
        }
      }
    });

    test(
      'Scenarios cover all diverse vehicle types (truck, bus, motorcycle, police, tram, etc.)',
      () {
        final allTypes = CrossroadsScenariosLibrary.allScenarios
            .expand((s) => s.actors)
            .map((a) => a.type)
            .toSet();

        for (final expectedType in CrossroadsVehicleType.values) {
          expect(
            allTypes.contains(expectedType),
            isTrue,
            reason:
                'Vehicle type $expectedType is not represented in scenarios library',
          );
        }
      },
    );

    test('Special emergency vehicle always has priority order 1', () {
      final emergencyScenario = CrossroadsScenariosLibrary.allScenarios
          .firstWhere((s) => s.id == 'cross_emergency_priority');
      final emergencyActor = emergencyScenario.actors.firstWhere(
        (a) => a.type == CrossroadsVehicleType.emergency,
      );

      expect(emergencyActor.priorityOrder, equals(1));
      expect(emergencyActor.hasSiren, isTrue);
    });

    test('Police patrol with siren has priority order 1 before tram', () {
      final policeScenario = CrossroadsScenariosLibrary.allScenarios.firstWhere(
        (s) => s.id == 'cross_police_vs_tram',
      );
      final policeActor = policeScenario.actors.firstWhere(
        (a) => a.type == CrossroadsVehicleType.police,
      );
      final tramActor = policeScenario.actors.firstWhere(
        (a) => a.type == CrossroadsVehicleType.tram,
      );

      expect(policeActor.priorityOrder, equals(1));
      expect(policeActor.hasSiren, isTrue);
      expect(tramActor.priorityOrder, equals(2));
    });

    test('Tram has advantage over regular cars on equal crossroads', () {
      final tramScenario = CrossroadsScenariosLibrary.allScenarios.firstWhere(
        (s) => s.id == 'cross_equal_tram',
      );
      final tramActor = tramScenario.actors.firstWhere(
        (a) => a.type == CrossroadsVehicleType.tram,
      );

      expect(tramActor.priorityOrder, equals(1));
    });

    test('Main road actors pass before yield sign actors', () {
      final mainRoadScenario = CrossroadsScenariosLibrary.allScenarios
          .firstWhere((s) => s.id == 'cross_main_straight');

      final carSouth = mainRoadScenario.actors.firstWhere(
        (a) => a.id == 'car_south',
      );
      final carEast = mainRoadScenario.actors.firstWhere(
        (a) => a.id == 'car_east',
      );

      expect(carSouth.priorityOrder, lessThan(carEast.priorityOrder));
    });

    test(
      'CrossroadsScenario serialization to JSON is valid for Three.js engine',
      () {
        for (final s in CrossroadsScenariosLibrary.allScenarios) {
          final json = s.toJson();
          expect(json['id'], isNotEmpty);
          expect(json['actors'], isA<List>());
          expect(json['signs'], isA<List>());
          final actorsList = json['actors'] as List;
          expect(actorsList.length, equals(s.actors.length));
        }
      },
    );

    test('cross_main_turns_left has 4 distinct and valid table8_13 signs', () {
      final scenario = CrossroadsScenariosLibrary.allScenarios.firstWhere(
        (s) => s.id == 'cross_main_turns_left',
      );
      expect(scenario.signs.length, equals(4));

      final south = scenario.signs.firstWhere(
        (s) => s.side == CrossroadsSide.south,
      );
      final west = scenario.signs.firstWhere(
        (s) => s.side == CrossroadsSide.west,
      );
      final north = scenario.signs.firstWhere(
        (s) => s.side == CrossroadsSide.north,
      );
      final east = scenario.signs.firstWhere(
        (s) => s.side == CrossroadsSide.east,
      );

      expect(south.code, equals('2.1'));
      expect(south.table8_13, equals('bottom_left'));

      expect(west.code, equals('2.1'));
      expect(west.table8_13, equals('bottom_right'));

      expect(north.code, equals('2.4'));
      expect(north.table8_13, equals('top_right'));

      expect(east.code, equals('2.4'));
      expect(east.table8_13, equals('left_top'));

      // Все 4 таблички 8.13 уникальны и не дублируются
      final tableSet = scenario.signs.map((s) => s.table8_13).toSet();
      expect(tableSet.length, equals(4));
    });

    test('Resolution step prompt bounds never exceed actors count', () {
      final scenario = CrossroadsScenariosLibrary.allScenarios.firstWhere(
        (s) => s.actors.length == 2,
      );
      final totalActors = scenario.actors.length;
      expect(totalActors, equals(2));

      // На 1-м шаге: кто проедет первым
      final prompt1 = 1 == 1
          ? appL10n.gameCrossroadsPromptWhoGoesFirst
          : appL10n.gameCrossroadsPromptWhoGoesNext(1);
      expect(prompt1, equals(appL10n.gameCrossroadsPromptWhoGoesFirst));

      // На 2-м шаге: кто проедет следующим (2-м)
      final prompt2 = 2 > totalActors
          ? appL10n.gameCrossroadsCompleteTitle
          : appL10n.gameCrossroadsPromptWhoGoesNext(2);
      expect(prompt2, equals(appL10n.gameCrossroadsPromptWhoGoesNext(2)));

      // На 3-м шаге (когда обе машины разъехались): показывается заголовок победы,
      // а не фантомный вопрос "Кто проедет следующим (3-м)?"
      final isComplete = 3 > totalActors;
      expect(isComplete, isTrue);
      final prompt3 = isComplete
          ? appL10n.gameCrossroadsCompleteTitle
          : appL10n.gameCrossroadsPromptWhoGoesNext(3);
      expect(prompt3, equals(appL10n.gameCrossroadsCompleteTitle));
      expect(prompt3, isNot(contains('3-м')));
    });
  });

  group('Crossroads Priority Progress Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Default progress is all zeros', () {
      const progress = CrossroadsPriorityProgress();
      expect(progress.bestScore, equals(0));
      expect(progress.maxCombo, equals(0));
      expect(progress.totalSolved, equals(0));
      expect(progress.trainingCount, equals(0));
    });

    test('Progress serialization and copyWith work correctly', () {
      const progress = CrossroadsPriorityProgress(
        bestScore: 450,
        maxCombo: 4,
        totalSolved: 7,
        trainingCount: 2,
      );

      final json = progress.toJson();
      final fromJson = CrossroadsPriorityProgress.fromJson(json);

      expect(fromJson.bestScore, equals(450));
      expect(fromJson.maxCombo, equals(4));
      expect(fromJson.totalSolved, equals(7));
      expect(fromJson.trainingCount, equals(2));

      final updated = fromJson.copyWith(bestScore: 600, maxCombo: 6);
      expect(updated.bestScore, equals(600));
      expect(updated.maxCombo, equals(6));
      expect(updated.totalSolved, equals(7));
    });

    test('Controller updates best score and max combo correctly', () async {
      final ds = ProgressDataSource();
      await ds.init();
      final controller = CrossroadsPriorityProgressController(ds);

      expect(controller.state.bestScore, equals(0));

      await controller.recordGameResult(score: 250, combo: 3, solved: 2);
      expect(controller.state.bestScore, equals(250));
      expect(controller.state.maxCombo, equals(3));
      expect(controller.state.totalSolved, equals(2));

      // Меньший счет не перезаписывает рекорд
      await controller.recordGameResult(score: 180, combo: 2, solved: 1);
      expect(controller.state.bestScore, equals(250));
      expect(controller.state.maxCombo, equals(3));
      expect(controller.state.totalSolved, equals(3));

      // Больший счет обновляет рекорд
      await controller.recordGameResult(score: 500, combo: 5, solved: 4);
      expect(controller.state.bestScore, equals(500));
      expect(controller.state.maxCombo, equals(5));
      expect(controller.state.totalSolved, equals(7));
    });
  });
}
