import 'package:flutter_test/flutter_test.dart';
import 'package:pdd_app/data/models/question.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/services/city_question_progress_service.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/data/sources/questions_data_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Bank extends QuestionsDataSource {
  @override
  Future<List<Question>> loadTickets(
    TicketCategory category, [
    String? lang,
  ]) async {
    expect(category, TicketCategory.ab);
    return [
      for (var n = 1; n <= 2; n++)
        Question(
          id: n == 1 ? 'canonical:v:ticket_1_1' : 'canonical-two',
          question: 'Question $n',
          ticketNumber: 1,
          questionNumber: n,
          answers: const [
            Answer(text: 'No', isCorrect: false),
            Answer(text: 'Yes', isCorrect: true),
          ],
        ),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProgressDataSource data;
  late CityQuestionProgressService service;
  late int start;
  Map<String, Object> entry(String scene, bool correct, int time) => {
    'situation': scene,
    'correct': correct,
    'answeredAt': time,
  };
  Map<String, Object> run(List<Object> log) => {
    'run_started': true,
    'answer_log': log,
  };
  Future<Map<String, dynamic>?> first() =>
      data.getQuestionProgress('canonical:v:ticket_1_1', TicketCategory.ab);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    data = ProgressDataSource();
    await data.init();
    service = CityQuestionProgressService(data, _Bank());
    start = DateTime.now().millisecondsSinceEpoch - 60000;
  });

  test(
    'city resolves real A/B and variant IDs; unknown scenes and mini-games cannot create mistakes',
    () async {
      await service.importSummary(
        run([
          entry('ticket_1_1', false, start),
          entry('ticket_1_2', true, start + 1),
          entry('sign_8_4_6', false, start + 2),
          entry('ticket_41_1', false, start + 3),
          {
            'situation': 'ticket_1_1',
            'correct': 'false',
            'answeredAt': start + 4,
          },
          {'situation': 'ticket_1_1', 'correct': false, 'answeredAt': -1},
        ]),
      );
      expect((await first())!['isCorrect'], false);
      expect((await first())!['source'], 'city');
      expect((await first())!['selectedAnswerIndex'], -1);
      expect(
        (await data.getAllQuestionProgress(TicketCategory.ab)).keys,
        unorderedEquals(['canonical:v:ticket_1_1', 'canonical-two']),
      );
      expect(await data.getAllQuestionProgress(TicketCategory.cd), isEmpty);
      await service.importSummary({
        ...run([entry('ticket_1_1', true, start + 100)]),
        'game': 'crossroads',
      });
      expect((await first())!['isCorrect'], false);
    },
  );

  test(
    'resume and repeated exit summaries count once; a new correct city answer removes the mistake',
    () async {
      final wrong = entry('ticket_1_1', false, start);
      await service.importSummary(run([wrong]));
      await service.importSummary(run([wrong]));
      expect((await first())!['attemptsCount'], 1);
      final corrected = run([wrong, entry('ticket_1_1', true, start + 1)]);
      await service.importSummary(corrected);
      expect((await first())!['isCorrect'], true);
      expect((await first())!['selectedAnswerIndex'], 1);
      expect((await first())!['attemptsCount'], 2);
      expect((await first())!['wrongAttempts'], 1);
      await service.importSummary({
        ...run([]),
        'city_runs': [corrected],
      });
      expect((await first())!['attemptsCount'], 2);
    },
  );

  test('late summaries never undo a training correction or reset', () async {
    final old = run([entry('ticket_1_1', false, start)]);
    await service.importSummary(old);
    await data.saveAnswer(
      questionId: 'canonical:v:ticket_1_1',
      isCorrect: true,
      selectedAnswerIndex: 1,
      category: TicketCategory.ab,
    );
    final corrected = await first();
    await service.importSummary(old);
    expect(await first(), corrected);
    await data.resetAllProgress();
    await service.importSummary(old);
    expect(await data.getAllQuestionProgress(TicketCategory.ab), isEmpty);
  });
}
