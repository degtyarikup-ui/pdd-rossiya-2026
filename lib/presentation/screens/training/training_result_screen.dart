import 'package:flutter/material.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/data/services/usage_reporter.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/training/training_screen.dart';
import 'package:pdd_app/presentation/widgets/result_share.dart';
import 'package:pdd_app/presentation/widgets/result_stage.dart';

/// Итог пройденного набора: билета, темы, избранного, работы над ошибками.
///
/// Раньше «Завершить» просто закрывало экран, и человек оставался без ответа
/// на вопрос «ну и как я прошёл?». Для экзамена результат был, а для билета —
/// нет, хотя билет проходят ровно с тем же намерением.
///
/// Оформление — общий завершающий экран игр ([ResultStage]): синий, если
/// набор пройден с долей ошибок не выше экзаменационной, иначе красный.
class TrainingResultScreen extends StatelessWidget {
  const TrainingResultScreen({
    super.key,
    required this.title,
    required this.total,
    required this.correct,
    required this.wrongQuestions,
  });

  /// Название набора — «Билет 1», название темы и т.п.
  final String title;

  final int total;
  final int correct;

  /// Вопросы, где ошиблись: по ним предлагаем пройти ещё раз.
  final List<Map<String, dynamic>> wrongQuestions;

  /// Пройден ли набор по мерке экзамена: на билете из 20 — не больше двух
  /// ошибок, на теме из 50 — не больше пяти.
  static bool passed({required int total, required int wrong}) {
    final rules = CountryConfig.current.examRules;
    return wrong * rules.mainCount <= rules.maxMistakes * total;
  }

  @override
  Widget build(BuildContext context) {
    final wrong = wrongQuestions.length;
    final success = passed(total: total, wrong: wrong);
    final background = success ? ResultStage.success : ResultStage.failure;

    void close() => Navigator.pop(context);

    return Scaffold(
      backgroundColor: background,
      body: ResultStage(
        background: background,
        spinRays: false,
        rays: success,
        title: title,
        emblem: ResultVerdictEmblem(passed: success),
        badge: ResultBadge(
          value: correct,
          suffix: '/$total',
          color: Colors.white,
          foreground: background,
          semanticsLabel: '${appL10n.correctAnswers}: $correct / $total',
        ),
        stats: [
          ResultStat(appL10n.correctAnswers, '$correct'),
          ResultStat(appL10n.wrongAnswers, '$wrong'),
        ],
        leading: [
          ResultHeaderButton(
            icon: Icons.ios_share_rounded,
            tooltip: appL10n.share,
            onPressed: () => shareStudyResult(
              context,
              passed: success,
              title: title,
              correct: correct,
              total: total,
              wrong: wrong,
            ),
          ),
        ],
        closeTooltip: appL10n.close,
        onClose: close,
        actions: [
          if (wrong > 0)
            ResultButton(
              label: appL10n.trainingRepeatMistakes,
              icon: Icons.replay_rounded,
              primary: false,
              onPressed: () {
                // pushReplacement, а не push: возвращаться к итогу старого
                // прохода после нового незачем.
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TrainingScreen(
                      questions: wrongQuestions,
                      title: appL10n.mistakes,
                      usageFeature: UsageFeature.mistakes,
                    ),
                  ),
                );
              },
            ),
          ResultButton(
            label: appL10n.done,
            primary: true,
            accent: background,
            onPressed: close,
          ),
        ],
      ),
    );
  }
}
