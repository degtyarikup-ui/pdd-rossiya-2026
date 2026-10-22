import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';

/// Общая настройка озвучки из шапки любого формата вопросов.
class QuestionVoiceToggle extends ConsumerWidget {
  const QuestionVoiceToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(
      appSettingsProvider.select((settings) => settings.voiceEnabled),
    );
    final colors = AppColors.of(context);

    return Tooltip(
      message: enabled ? appL10n.gameVoiceOn : appL10n.gameVoiceOff,
      child: Semantics(
        toggled: enabled,
        child: AppChromeIconButton(
          icon: enabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          backgroundColor: enabled ? colors.accentSurface10 : null,
          iconColor: enabled ? colors.accent : colors.secondaryText,
          onTap: () {
            HapticFeedbackHelper.select();
            ref
                .read(appSettingsProvider.notifier)
                .setVoiceEnabled(!ref.read(appSettingsProvider).voiceEnabled);
          },
        ),
      ),
    );
  }
}
