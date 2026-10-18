import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/services/game_garage_service.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final garage = GameGarageService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    garage.resetForTest();
  });

  test('starter and exactly six shared paints', () async {
    await garage.load();
    expect(GameGarageService.paints.length, 6);
    expect(
      GameGarageService.paints.toSet(),
      GameGarageService.paintHex.keys.toSet(),
    );
    expect(garage.ownedModels, ['hatch']);
    expect(garage.ownedPaints, ['red']);
    expect(garage.nextReward!.model, 'sedan');
    expect(garage.correctUntilNext, 5);
    expect(garage.owns('hatch', 'unknown'), isFalse);
    expect(garage.owns('unknown', 'red'), isFalse);
  });

  test(
    'correct answers outside Living City do not earn garage rewards',
    () async {
      final progress = ProgressDataSource();
      await progress.init();
      for (var i = 0; i < 10; i++) {
        await progress.saveAnswer(
          questionId: 'q_1_1',
          isCorrect: true,
          selectedAnswerIndex: 0,
          category: TicketCategory.ab,
        );
      }
      await garage.load();
      expect(garage.correctTotal, 0);
      expect(garage.ownedModels, ['hatch']);
      expect(garage.ownedPaints, ['red']);
    },
  );

  test(
    'milestones alternate model and global paint without duplicates',
    () async {
      expect(await garage.recordCorrectAnswers(4), isEmpty);
      var rewards = await garage.recordCorrectAnswers(1);
      expect(rewards.single.model, 'sedan');
      expect(garage.correctUntilNext, 5);
      expect(garage.owns('sedan', 'red'), isTrue);
      rewards = await garage.recordCorrectAnswers(5);
      expect(rewards.single.paint, 'blue');
      expect(garage.owns('hatch', 'blue'), isTrue);
      expect(garage.owns('sedan', 'blue'), isTrue);
      rewards = await garage.recordCorrectAnswers(10);
      expect(rewards.single.model, 'wagon');
      expect(garage.owns('wagon', 'blue'), isTrue);
      expect(garage.cars.map((c) => c.key).toSet().length, 6);
      expect(await garage.recordCorrectAnswers(0), isEmpty);
      expect(await garage.recordCorrectAnswers(-5), isEmpty);
      expect(garage.correctTotal, 20);
    },
  );

  test(
    'one batch crosses milestones, exhausts rewards and survives reload',
    () async {
      final earned = await garage.recordCorrectAnswers(420);
      expect(earned.length, GameGarageService.rewards.length);
      expect(garage.ownedModels, GameGarageService.models);
      expect(garage.ownedPaints, GameGarageService.paints);
      expect(garage.cars.length, 36);
      expect(garage.nextReward, isNull);
      expect(garage.correctUntilNext, 0);
      expect(await garage.recordCorrectAnswers(1000), isEmpty);
      garage.invalidate();
      await garage.load();
      expect(garage.correctTotal, 1420);
      expect(garage.cars.length, 36);
      expect(garage.nextReward, isNull);
      final prefs = await SharedPreferences.getInstance();
      final cars = jsonDecode(prefs.getString('game_garage_cars')!) as List;
      expect(cars.length, 36);
      expect(prefs.getInt('game_garage_unlocks'), 10);
    },
  );

  test(
    'legacy pairs preserve models and map every old shade globally',
    () async {
      SharedPreferences.setMockInitialValues({
        'game_garage_cars': jsonEncode([
          {'id': 'pickup', 'paint': 'sand'},
          {'id': 'suv', 'paint': 'orange'},
          {'id': 'coupe', 'paint': 'purple'},
          {'id': 'sedan', 'paint': 'teal'},
          {'id': 'cyber', 'paint': 'gold'},
          {'id': 'bogus', 'paint': 'red'},
          {'id': 'wagon', 'paint': 'bogus'},
        ]),
        'game_garage_correct': 2,
        'game_garage_unlocks': 99,
      });
      await garage.load();
      expect(garage.ownedModels.toSet(), {
        'hatch',
        'pickup',
        'suv',
        'coupe',
        'sedan',
        'cyber',
      });
      expect(garage.ownedPaints.toSet(), {'red', 'green', 'yellow'});
      for (final id in garage.ownedModels) {
        for (final paint in garage.ownedPaints) {
          expect(garage.owns(id, paint), isTrue);
        }
      }
      expect(garage.correctTotal, 2);
      // Grandfathered sedan is not awarded again; the next missing item is blue.
      expect(garage.nextReward!.paint, 'blue');
      expect(garage.correctUntilNext, 8);
      garage.invalidate();
      await garage.load();
      expect(garage.cars.length, 18);
    },
  );

  test('historical correct answers grant all due milestones on load', () async {
    SharedPreferences.setMockInitialValues({
      'game_garage_cars': '[{"id":"pickup","paint":"silver"}]',
      'game_garage_correct': 80,
      'game_garage_unlocks': 1,
    });
    await garage.load();
    expect(garage.ownedModels.toSet(), {
      'hatch',
      'sedan',
      'wagon',
      'coupe',
      'pickup',
    });
    expect(garage.ownedPaints.toSet(), {
      'red',
      'blue',
      'white',
      'black',
    });
    expect(garage.nextReward!.model, 'suv');
    expect(garage.correctUntilNext, 30);
    expect(await garage.recordCorrectAnswers(1), isEmpty);
  });

  test('corrupt collection cannot erase valid answer count', () async {
    SharedPreferences.setMockInitialValues({
      'game_garage_cars': '{broken',
      'game_garage_correct': 10,
    });
    await garage.load();
    expect(garage.correctTotal, 10);
    expect(garage.ownedModels, ['hatch', 'sedan']);
    expect(garage.ownedPaints, ['red', 'blue']);
  });

  test('simultaneous batches never lose answers or repeat rewards', () async {
    final results = await Future.wait([
      garage.recordCorrectAnswers(5),
      garage.recordCorrectAnswers(5),
      garage.recordCorrectAnswers(10),
    ]);
    expect(results.expand((r) => r).length, 3);
    expect(garage.correctTotal, 20);
    garage.invalidate();
    await garage.load();
    expect(garage.correctTotal, 20);
    expect(garage.cars.length, 6);
  });

  test('cloud union of legacy pairs extends colours across models', () async {
    await garage.recordCorrectAnswers(5);
    final prefs = await SharedPreferences.getInstance();
    final local = jsonDecode(prefs.getString('game_garage_cars')!) as List;
    await prefs.setString(
      'game_garage_cars',
      jsonEncode([
        ...local,
        {'id': 'pickup', 'paint': 'teal'},
      ]),
    );
    garage.invalidate();
    await garage.load();
    expect(garage.owns('hatch', 'green'), isTrue);
    expect(garage.owns('sedan', 'green'), isTrue);
    expect(garage.owns('pickup', 'red'), isTrue);
    expect(garage.owns('pickup', 'green'), isTrue);
  });
}
