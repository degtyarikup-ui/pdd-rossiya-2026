import 'package:pdd_app/data/models/question.dart';
import 'package:pdd_app/data/models/question_answer_source.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/sources/progress_data_source.dart';
import 'package:pdd_app/data/sources/questions_data_source.dart';

/// Imports actual city-card answers, including runs completed before a replay.
/// Scene references resolve to the canonical A/B bank, never to synthetic IDs.
class CityQuestionProgressService {
  CityQuestionProgressService(this.progress, this.questions);

  final ProgressDataSource progress;
  final QuestionsDataSource questions;

  Future<void> importSummary(Map summary) async {
    if (summary['run_started'] != true || summary['game'] != null) return;
    final previous = summary['city_runs'];
    final runs = <Map>[
      if (previous is List) ...previous.whereType<Map>(),
      summary,
    ];
    final entries = <Map>[
      for (final run in runs)
        if (run['run_started'] == true &&
            run['game'] == null &&
            run['answer_log'] is List)
          ...(run['answer_log'] as List).whereType<Map>(),
    ];
    if (entries.isEmpty) return;
    final bank = await questions.loadTickets(TicketCategory.ab);
    final byScene = <String, Question>{
      for (final question in bank)
        'ticket_${question.ticketNumber}_${question.questionNumber}': question,
    };
    for (final entry in entries) {
      final question = byScene[entry['situation']];
      final correct = entry['correct'];
      final stamp = entry['answeredAt'];
      if (question == null ||
          correct is! bool ||
          stamp is! int ||
          stamp <= 0 ||
          stamp > 8640000000000000) {
        continue;
      }
      await progress.saveAnswer(
        questionId: question.id,
        isCorrect: correct,
        // Game options can differ from the ticket's wording and order.
        selectedAnswerIndex: correct ? question.correctAnswerIndex : -1,
        category: TicketCategory.ab,
        source: QuestionAnswerSource.city,
        answeredAt: DateTime.fromMillisecondsSinceEpoch(stamp),
      );
    }
  }
}
