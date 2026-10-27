import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/data/models/marathon_progress.dart';
import 'package:pdd_app/data/models/question.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/data/services/usage_reporter.dart';
import 'package:pdd_app/presentation/screens/training/training_result_screen.dart';
import 'package:pdd_app/presentation/screens/training/training_screen.dart';

/// All ticket positions, including illustration variants, in their printed order.
List<Map<String, dynamic>> marathonQuestions(Iterable<Question> questions) {
  final ordered = questions.toList()
    ..sort((a, b) {
      final ticket = a.ticketNumber.compareTo(b.ticketNumber);
      return ticket != 0
          ? ticket
          : a.questionNumber.compareTo(b.questionNumber);
    });
  return ordered.map((q) => q.toMap()).toList();
}

Future<void> openMarathon(BuildContext context, WidgetRef ref) async {
  final category = ref.read(appSettingsProvider).ticketCategory;
  final tickets = await ref.read(ticketsProvider.future);
  if (!context.mounted ||
      ref.read(appSettingsProvider).ticketCategory != category) {
    return;
  }
  final questions = marathonQuestions(
    tickets.expand((ticket) => (ticket['questions'] as List).cast<Question>()),
  );
  if (questions.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(appL10n.noQuestions)));
    return;
  }
  final source = ref.read(progressDataSourceProvider);
  var progress = source.loadMarathon(category);
  final choices = progress?.restoreChoices(questions);
  final answered = choices?.whereType<int>().length ?? 0;
  if (answered == 0) progress = null;
  if (progress != null && choices != null) {
    final resume = await showDialog<bool>(
      context: context,
      builder: (_) =>
          MarathonResumeDialog(answered: answered, total: questions.length),
    );
    if (resume == null || !context.mounted) return;
    if (!resume) {
      progress = null;
    } else if (answered == questions.length) {
      final wrong = <Map<String, dynamic>>[
        for (var i = 0; i < questions.length; i++)
          if ((questions[i]['answers'] as List)[choices[i]!]['correct'] != true)
            questions[i],
      ];
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TrainingResultScreen(
            title: appL10n.marathon,
            total: questions.length,
            correct: questions.length - wrong.length,
            wrongQuestions: wrong,
          ),
        ),
      );
      return;
    }
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TrainingScreen(
        questions: questions,
        title: appL10n.marathon,
        usageFeature: UsageFeature.marathon,
        marathonCategory: category,
        marathonProgress: progress ?? const MarathonProgress(),
      ),
    ),
  );
}

class MarathonResumeDialog extends StatelessWidget {
  const MarathonResumeDialog({
    super.key,
    required this.answered,
    required this.total,
  });
  final int answered;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final complete = answered == total;
    return AlertDialog(
      scrollable: true,
      backgroundColor: colors.cardBackground,
      icon: SvgPicture.asset(
        'assets/images/home_icon_marathon.svg',
        width: 36,
        height: 36,
      ),
      title: Text(
        complete ? appL10n.marathonCompleted : appL10n.marathonResumeTitle,
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              appL10n.marathonProgress(answered, total),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : answered / total,
                minHeight: 6,
                color: colors.accent,
                backgroundColor: colors.accentSurface10,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                complete ? appL10n.marathonViewResults : appL10n.continueButton,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: colors.secondaryText,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    AppDimensions.buttonRadius,
                  ),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(appL10n.marathonRestart, textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}
