import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/crossroads_priority_model.dart';
import 'package:pdd_app/data/models/crossroads_priority_progress.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Crossroads Priority Rules and Scenarios Tests', () {
    test('All certified scenarios have valid priority order sequences', () {
      final scenarios = CrossroadsScenariosLibrary.allScenarios;
      expect(scenarios.length, greaterThanOrEqualTo(8));

      for (final s in scenarios) {
        expect(s.actors.isNotEmpty, isTrue, reason: 'Scenario ${s.id} has no actors');
        final orders = s.actors.map((a) => a.priorityOrder).toList()..sort();
        // Проверяем, что порядок идет 1, 2, 3...
        for (int i = 0; i < orders.length; i++) {
          expect(orders[i], equals(i + 1),
              reason: 'Scenario ${s.id} has broken priority order sequence: $orders');
        }
      }
    });

    test('Special emergency vehicle always has priority order 1', () {
      final emergencyScenario = CrossroadsScenariosLibrary.allScenarios
          .firstWhere((s) => s.id == 'cross_emergency_priority');
      final emergencyActor = emergencyScenario.actors
          .firstWhere((a) => a.type == CrossroadsVehicleType.emergency);

      expect(emergencyActor.priorityOrder, equals(1));
      expect(emergencyActor.hasSiren, isTrue);
    });

    test('Tram has advantage over regular cars on equal crossroads', () {
      final tramScenario = CrossroadsScenariosLibrary.allScenarios
          .firstWhere((s) => s.id == 'cross_equal_tram');
      final tramActor = tramScenario.actors
          .firstWhere((a) => a.type == CrossroadsVehicleType.tram);

      expect(tramActor.priorityOrder, equals(1));
    });

    test('Main road actors pass before yield sign actors', () {
      final mainRoadScenario = CrossroadsScenariosLibrary.allScenarios
          .firstWhere((s) => s.id == 'cross_main_straight');

      final carSouth = mainRoadScenario.actors.firstWhere((a) => a.id == 'car_south');
      final carEast = mainRoadScenario.actors.firstWhere((a) => a.id == 'car_east');

      expect(carSouth.priorityOrder, lessThan(carEast.priorityOrder));
    });

    test('CrossroadsScenario serialization to JSON is valid for Three.js engine', () {
      for (final s in CrossroadsScenariosLibrary.allScenarios) {
        final json = s.toJson();
        expect(json['id'], isNotEmpty);
        expect(json['actors'], isA<List>());
        expect(json['signs'], isA<List>());
        final actorsList = json['actors'] as List;
        expect(actorsList.length, equals(s.actors.length));
      }
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
