import 'dart:math';

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

/// Shuffle new runs once; restore saved runs by ID, including legacy order.
List<Map<String, dynamic>> marathonQuestions(
  Iterable<Question> questions, {
  MarathonProgress? progress,
  Random? random,
}) {
  final ordered = questions.toList()
    ..sort((a, b) {
      final ticket = a.ticketNumber.compareTo(b.ticketNumber);
      return ticket != 0
          ? ticket
          : a.questionNumber.compareTo(b.questionNumber);
    });
  if (progress == null) {
    ordered.shuffle(random);
    return ordered.map((q) => q.toMap()).toList();
  }
  // Legacy runs keep their printed order so their answered prefix is intact.
  // New content is appended; removed IDs and duplicate saved IDs are skipped.
  final remaining = {for (final question in ordered) question.id: question};
  return [
    for (final id in progress.questionOrder)
      if (remaining.containsKey(id)) remaining.remove(id)!.toMap(),
    for (final question in remaining.values) question.toMap(),
  ];
}

Future<void> openMarathon(BuildContext context, WidgetRef ref) async {
  final category = ref.read(appSettingsProvider).ticketCategory;
  final tickets = await ref.read(ticketsProvider.future);
  if (!context.mounted ||
      ref.read(appSettingsProvider).ticketCategory != category) {
    return;
  }
  final source = ref.read(progressDataSourceProvider);
  var progress = source.loadMarathon(category);
  if (progress != null &&
      progress.answers.isEmpty &&
      progress.questionOrder.isEmpty) {
    progress = null;
  }
  final bank = tickets
      .expand((ticket) => (ticket['questions'] as List).cast<Question>())
      .toList();
  var questions = marathonQuestions(bank, progress: progress);
  if (questions.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(appL10n.noQuestions)));
    return;
  }
  final choices = progress?.restoreChoices(questions);
  final answered = choices?.whereType<int>().length ?? 0;
  if (answered > 0 && progress != null && choices != null) {
    final resume = await showDialog<bool>(
      context: context,
      builder: (_) =>
          MarathonResumeDialog(answered: answered, total: questions.length),
    );
    if (resume == null || !context.mounted) return;
    if (!resume) {
      progress = null;
      questions = marathonQuestions(bank);
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
    final progressLabel = appL10n.marathonProgress(answered, total);
    return Dialog(
      backgroundColor: colors.cardBackground,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusExtraLarge),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.lightAccent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: SvgPicture.asset(
                      'assets/images/home_icon_marathon.svg',
                      colorFilter: ColorFilter.mode(
                        colors.accent,
                        BlendMode.srcIn,
                      ),
                      excludeFromSemantics: true,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: appL10n.close,
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      foregroundColor: colors.secondaryText,
                      minimumSize: const Size(48, 48),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 22),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Semantics(
                namesRoute: true,
                header: true,
                child: Text(
                  complete
                      ? appL10n.marathonCompleted
                      : appL10n.marathonResumeTitle,
                  style: TextStyle(
                    fontSize: 22,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                progressLabel,
                style: TextStyle(
                  fontSize: 34,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: 12),
              ExcludeSemantics(
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : (answered / total).clamp(0.0, 1.0),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(6),
                  color: colors.accent,
                  backgroundColor: colors.gray,
                ),
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  complete
                      ? appL10n.marathonViewResults
                      : appL10n.continueButton,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Color.lerp(
                    colors.secondaryText,
                    colors.primaryText,
                    0.25,
                  ),
                  minimumSize: const Size.fromHeight(48),
                  textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppDimensions.buttonRadius,
                    ),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  appL10n.marathonRestart,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
