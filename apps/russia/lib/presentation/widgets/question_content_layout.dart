import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';

/// One question and answer implementation, arranged for the available space.
/// Only the scrolling presentation changes; session state stays in its screen.
class QuestionContentLayout extends StatelessWidget {
  const QuestionContentLayout({
    super.key,
    required this.pageIndex,
    required this.question,
    required this.answers,
    this.image,
    this.explanation = const [],
    this.bottomSpace = AppDimensions.spacingXXL,
  });

  final int pageIndex;
  final Widget? image;
  final Widget question;
  final List<Widget> answers;
  final List<Widget> explanation;
  final double bottomSpace;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(18) / 18;
        final wide = scale <= 1.3
            ? constraints.maxWidth >= 720 ||
                  (constraints.maxWidth >= 600 && constraints.maxHeight < 420)
            : constraints.maxWidth >= 960;
        final prompt = <Widget>[
          if (image != null) ...[
            const SizedBox(height: AppDimensions.spacingM),
            if (wide)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: (constraints.maxHeight * .5).clamp(72, 300),
                ),
                child: image!,
              )
            else
              image!,
          ],
          const SizedBox(height: AppDimensions.spacingL),
          question,
          const SizedBox(height: AppDimensions.spacingL),
        ];
        if (!wide) {
          // Same spacing and scroll structure as the original phone page.
          return SingleChildScrollView(
            key: ValueKey<int>(pageIndex),
            padding: const EdgeInsets.all(AppDimensions.screenPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...prompt,
                ...answers,
                ...explanation,
                SizedBox(height: bottomSpace),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.screenPadding,
          ),
          child: Row(
            key: const ValueKey('question-wide-layout'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  key: PageStorageKey('question-prompt-$pageIndex'),
                  primary: false,
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: prompt,
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: SingleChildScrollView(
                  key: PageStorageKey('question-answers-$pageIndex'),
                  primary: false,
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...answers,
                      ...explanation,
                      SizedBox(height: bottomSpace),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
