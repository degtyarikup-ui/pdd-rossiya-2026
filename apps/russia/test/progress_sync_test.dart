import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/models/traffic_controller_progress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/data/services/game_garage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GameGarageService.instance.resetForTest();
  });

  test('ProgressDataSource export and import snapshot works correctly', () async {
    final ds1 = ProgressDataSource();
    await ds1.init();

    // 1. Answer question in ds1
    await ds1.saveAnswer(
      questionId: 'q_1_1',
      isCorrect: true,
      selectedAnswerIndex: 2,
      category: TicketCategory.ab,
    );

    // 2. Save ticket progress
    await ds1.saveTicketProgress(
      ticketNumber: 1,
      correctAnswers: 20,
      totalAnswered: 20,
      category: TicketCategory.ab,
    );

    // 3. Save favorite
    await ds1.toggleFavorite('q_1_5', TicketCategory.ab);

    // 4. Save exam result
    await ds1.saveExamResult(
      ticketNumber: 5,
      correctAnswers: 20,
      wrongAnswers: 0,
      passed: true,
      category: TicketCategory.ab,
    );

    // 5. Export snapshot from ds1
    final snapshot = ds1.exportProgressSnapshot();
    expect(snapshot['questionProgressAb'], isNotEmpty);
    expect(snapshot['ticketProgressAb'], isNotEmpty);
    expect(snapshot['favoritesAb'], contains('q_1_5'));
    expect(snapshot['examResultsAb'], isNotEmpty);

    // 6. Simulate fresh device / reinstall: clear SharedPreferences and initialize ds2
    SharedPreferences.setMockInitialValues({});
    final ds2 = ProgressDataSource();
    await ds2.init();

    expect(await ds2.isQuestionAnswered('q_1_1', TicketCategory.ab), isFalse);
    expect(await ds2.isFavorite('q_1_5', TicketCategory.ab), isFalse);

    // 7. Import snapshot on fresh device (simulating cloud sync after login)
    await ds2.importProgressSnapshot(snapshot);

    expect(await ds2.isQuestionAnswered('q_1_1', TicketCategory.ab), isTrue);
    final qp = await ds2.getQuestionProgress('q_1_1', TicketCategory.ab);
    expect(qp?['isCorrect'], isTrue);
    expect(qp?['selectedAnswerIndex'], 2);

    expect(await ds2.isFavorite('q_1_5', TicketCategory.ab), isTrue);
    expect(await ds2.getTicketCorrectAnswers(1, TicketCategory.ab), 20);
  });

  test(
    'delayed sync cannot erase an answer or restore a removed favorite',
    () async {
      final ds = ProgressDataSource();
      await ds.init();
      await ds.saveAnswer(
        questionId: 'old',
        isCorrect: false,
        selectedAnswerIndex: 0,
        category: TicketCategory.ab,
      );
      await ds.toggleFavorite('old', TicketCategory.ab);
      final before = ds.exportProgressSnapshot();
      await ds.saveAnswer(
        questionId: 'old',
        isCorrect: true,
        selectedAnswerIndex: 1,
        category: TicketCategory.ab,
      );
      await ds.saveAnswer(
        questionId: 'new',
        isCorrect: true,
        selectedAnswerIndex: 1,
        category: TicketCategory.ab,
      );
      await ds.toggleFavorite('old', TicketCategory.ab);
      await ds.importProgressSnapshot(before);
      expect(
        (await ds.getQuestionProgress('old', TicketCategory.ab))!['isCorrect'],
        true,
      );
      expect(await ds.isQuestionAnswered('new', TicketCategory.ab), true);
      expect(await ds.isFavorite('old', TicketCategory.ab), false);
    },
  );

  test('reset survives delayed sync and keeps newly earned progress', () async {
    final ds = ProgressDataSource();
    await ds.init();
    await ds.saveAnswer(
      questionId: 'old',
      isCorrect: false,
      selectedAnswerIndex: 0,
      category: TicketCategory.ab,
    );
    await ds.toggleFavorite('old', TicketCategory.ab);
    final before = ds.exportProgressSnapshot();
    await ds.resetAllProgress();
    await ds.saveAnswer(
      questionId: 'new',
      isCorrect: true,
      selectedAnswerIndex: 1,
      category: TicketCategory.ab,
    );
    await ds.importProgressSnapshot(before);
    expect(await ds.isQuestionAnswered('old', TicketCategory.ab), false);
    expect(await ds.isQuestionAnswered('new', TicketCategory.ab), true);
    expect(await ds.isFavorite('old', TicketCategory.ab), false);
  });

  test(
    'mini game import refreshes an already read progress controller',
    () async {
      final ds = ProgressDataSource();
      await ds.init();
      await ds.saveTrafficControllerProgress(
        const TrafficControllerProgress(bestScore: 100, totalSolved: 2),
      );
      final container = ProviderContainer(
        overrides: [progressDataSourceProvider.overrideWithValue(ds)],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        trafficControllerProgressProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      expect(container.read(trafficControllerProgressProvider).bestScore, 100);
      await ds.importProgressSnapshot({
        'miniGames': {
          'regulator': {'bestScore': 500, 'totalSolved': 5},
        },
      });
      await Future<void>.delayed(Duration.zero);
      expect(container.read(trafficControllerProgressProvider).bestScore, 500);
      expect(container.read(trafficControllerProgressProvider).totalSolved, 5);
      expect(
        (ds.exportProgressSnapshot()['miniGames']
            as Map)['regulator']['bestScore'],
        500,
      );
    },
  );

  test('Game progress rides along: best score, garage union, counters', () async {
    SharedPreferences.setMockInitialValues({
      'game_best_score': 1200,
      'game_garage_cars':
          '[{"id":"hatch","paint":"red"},{"id":"suv","paint":"blue"}]',
      'game_garage_correct': 12,
      'game_garage_unlocks': 1,
    });
    final ds = ProgressDataSource();
    await ds.init();
    final snapshot = ds.exportProgressSnapshot();
    final game = snapshot['game'] as Map<String, dynamic>;
    expect(game['bestScore'], 1200);
    expect((game['garageCars'] as List).length, 2);

    // The cloud knows a higher score, another car and a further counter.
    await ds.importProgressSnapshot({
      'game': {
        'bestScore': 4110,
        'garageCars': [
          {'id': 'hatch', 'paint': 'red'},
          {'id': 'coupe', 'paint': 'teal'},
        ],
        'garageCorrect': 20,
        'garageUnlocks': 2,
        'vehicle': 'coupe',
        'vehiclePaint': 'teal',
      },
    });
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('game_best_score'), 4110);
    expect(prefs.getInt('game_garage_correct'), 20);
    expect(prefs.getInt('game_garage_unlocks'), 2);
    expect(
      prefs.getString('game_garage_cars'),
      '[{"id":"hatch","paint":"red"},{"id":"suv","paint":"blue"},{"id":"coupe","paint":"teal"}]',
    );
    expect(prefs.getString('game_vehicle'), 'coupe');

    // A lower cloud score never overwrites the local best.
    await ds.importProgressSnapshot({
      'game': {'bestScore': 10, 'garageCorrect': 1},
    });
    expect(prefs.getInt('game_best_score'), 4110);
    expect(prefs.getInt('game_garage_correct'), 20);
  });

  test('cloud garage import serializes with a local reward write', () async {
    SharedPreferences.setMockInitialValues({
      'game_garage_cars': '[{"id":"hatch","paint":"red"}]',
      'game_garage_correct': 4,
    });
    final ds = ProgressDataSource();
    await ds.init();
    final garage = GameGarageService.instance;
    await garage.load();

    // A local fifth answer starts persisting while a cloud response arrives
    // with a later total and a model/paint earned by an older client.
    await Future.wait([
      garage.recordCorrectAnswers(1),
      ds.importProgressSnapshot({
        'game': {
          'garageCorrect': 40,
          'garageCars': [
            {'id': 'pickup', 'paint': 'teal'},
          ],
        },
      }),
    ]);
    await garage.load();
    expect(garage.correctTotal, 40);
    expect(garage.owns('sedan', 'blue'), isTrue);
    expect(garage.owns('pickup', 'green'), isTrue);
    expect(garage.owns('sedan', 'green'), isTrue);
    expect(garage.owns('pickup', 'blue'), isTrue);

    // A delayed reply cannot undo the combined collection or its counter.
    await ds.importProgressSnapshot({
      'game': {
        'garageCorrect': 1,
        'garageCars': [
          {'id': 'hatch', 'paint': 'orange'},
        ],
      },
    });
    await garage.load();
    expect(garage.correctTotal, 40);
    expect(garage.owns('pickup', 'green'), isTrue);
    expect(garage.owns('sedan', 'blue'), isTrue);
  });
}
