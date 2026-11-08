import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Local to the active question route: dialogs and text entry keep their keys.
/// Repeating a held digit must never answer subsequent exam questions.
class QuestionKeyboardShortcuts extends StatelessWidget {
  const QuestionKeyboardShortcuts({
    super.key,
    required this.answerCount,
    required this.onAnswer,
    required this.onPrevious,
    required this.onNext,
    required this.child,
    this.onConfirm,
    this.onExit,
    this.enabled = kIsWeb,
  });

  final int answerCount;
  final ValueChanged<int> onAnswer;
  final VoidCallback onPrevious, onNext;
  final VoidCallback? onConfirm;
  final VoidCallback? onExit;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    void invoke(VoidCallback callback) {
      if (ModalRoute.of(context)?.isCurrent == false) return;
      final focus = FocusManager.instance.primaryFocus?.context;
      if (focus?.findAncestorWidgetOfExactType<EditableText>() != null) return;
      callback();
    }

    const digits = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    const numpad = [
      LogicalKeyboardKey.numpad1,
      LogicalKeyboardKey.numpad2,
      LogicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpad4,
      LogicalKeyboardKey.numpad5,
      LogicalKeyboardKey.numpad6,
      LogicalKeyboardKey.numpad7,
      LogicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad9,
    ];
    return CallbackShortcuts(
      bindings: {
        for (var i = 0; i < answerCount && i < digits.length; i++) ...{
          SingleActivator(digits[i], includeRepeats: false): () =>
              invoke(() => onAnswer(i)),
          SingleActivator(numpad[i], includeRepeats: false): () =>
              invoke(() => onAnswer(i)),
        },
        const SingleActivator(
          LogicalKeyboardKey.arrowLeft,
          includeRepeats: false,
        ): () =>
            invoke(onPrevious),
        const SingleActivator(
          LogicalKeyboardKey.arrowRight,
          includeRepeats: false,
        ): () =>
            invoke(onNext),
        if (onConfirm != null) ...{
          const SingleActivator(
            LogicalKeyboardKey.enter,
            includeRepeats: false,
          ): () =>
              invoke(onConfirm!),
          const SingleActivator(
            LogicalKeyboardKey.numpadEnter,
            includeRepeats: false,
          ): () =>
              invoke(onConfirm!),
        },
        if (onExit != null)
          const SingleActivator(
            LogicalKeyboardKey.escape,
            includeRepeats: false,
          ): () =>
              invoke(onExit!),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}

class QuestionKeyboardHint extends StatelessWidget {
  const QuestionKeyboardHint({super.key, this.training = false});
  final bool training;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb ||
        MediaQuery.sizeOf(context).width < 900 ||
        MediaQuery.sizeOf(context).height < 600) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Text(
        training ? appL10n.trainingKeyboardHint : appL10n.examKeyboardHint,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          color: AppColors.of(context).secondaryText,
        ),
      ),
    );
  }
}
