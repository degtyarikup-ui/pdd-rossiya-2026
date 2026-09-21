import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
}
