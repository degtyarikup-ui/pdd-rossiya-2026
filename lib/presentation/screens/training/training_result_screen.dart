import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/training/training_screen.dart';

/// Итог пройденного набора: билета, темы, избранного, работы над ошибками.
///
/// Раньше «Завершить» просто закрывало экран, и человек оставался без ответа
/// на вопрос «ну и как я прошёл?». Для экзамена результат был, а для билета —
/// нет, хотя билет проходят ровно с тем же намерением.
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

  @override
  Widget build(BuildContext context) {
    final wrong = wrongQuestions.length;
    final perfect = wrong == 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.screenPadding),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: perfect ? AppColors.green : AppColors.gold,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  perfect
                      ? Icons.check_rounded
                      : Icons.school_outlined,
                  size: 52,
                  color: AppColors.white,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingL),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: AppColors.primaryText,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingS),
              Text(
                perfect
                    ? appL10n.trainingResultPerfect
                    : appL10n.trainingResultWithMistakes,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: AppColors.secondaryText,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingXXL),
              Row(
                children: [
                  Expanded(
                    child: _ResultCell(
                      value: '$correct',
                      label: appL10n.progressCorrect,
                      color: AppColors.green,
                    ),
                  ),
                  const SizedBox(width: AppDimensions.spacingM),
                  Expanded(
                    child: _ResultCell(
                      value: '$wrong',
                      label: appL10n.progressWrong,
                      color: wrong > 0
                          ? AppColors.red
                          : AppColors.secondaryText,
                    ),
                  ),
                  const SizedBox(width: AppDimensions.spacingM),
                  Expanded(
                    child: _ResultCell(
                      value: '$total',
                      label: appL10n.progressDone,
                      color: AppColors.primaryText,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (wrong > 0) ...[
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton(
                    onPressed: () {
                      HapticFeedbackHelper.tap();
                      // pushReplacement, а не push: возвращаться к итогу
                      // старого прохода после нового незачем.
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TrainingScreen(
                            questions: wrongQuestions,
                            title: appL10n.mistakes,
                          ),
                        ),
                      );
                    },
                    child: Text(appL10n.trainingRepeatMistakes),
                  ),
                ),
                const SizedBox(height: AppDimensions.spacingM),
              ],
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    HapticFeedbackHelper.tap();
                    Navigator.pop(context);
                  },
                  child: Text(appL10n.done),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultCell extends StatelessWidget {
  const _ResultCell({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppDimensions.spacingL),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              height: 1.1,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}
