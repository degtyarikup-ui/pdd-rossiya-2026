import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/app_settings.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/presentation/widgets/app_toast.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/premium_paywall_sheet.dart';

String voiceSpeedLabel(double speed) => speed == speed.roundToDouble()
    ? speed.toInt().toString()
    : speed.toString();

/// One narration control across tickets, the exam, the feed and Settings.
/// A tap toggles playback; a hold opens the speed picker without toggling it.
class QuestionVoiceToggle extends ConsumerStatefulWidget {
  const QuestionVoiceToggle({super.key, this.onSheetVisibilityChanged});

  final ValueChanged<bool>? onSheetVisibilityChanged;

  @override
  ConsumerState<QuestionVoiceToggle> createState() =>
      _QuestionVoiceToggleState();
}

class _QuestionVoiceToggleState extends ConsumerState<QuestionVoiceToggle> {
  bool _pressed = false;
  bool _showingSheet = false;

  late final TtsService _narration;

  @override
  void initState() {
    super.initState();
    _narration = ref.read(ttsServiceProvider);
    _narration.status.addListener(_onNarrationStatus);
  }

  void _onNarrationStatus() {
    if (!mounted) return;
    final status = _narration.status.value;
    if (status != NarrationStatus.unavailable &&
        status != NarrationStatus.voiceUnavailable) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _narration.status.value != status ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      AppToast.show(
        context,
        status == NarrationStatus.voiceUnavailable
            ? appL10n.gameVoiceUnavailable
            : appL10n.voicePlaybackUnavailable,
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _narration.status.removeListener(_onNarrationStatus);
    super.dispose();
  }

  Future<void> _interact({bool speed = false}) async {
    if (_showingSheet) return;
    final settings = ref.read(appSettingsProvider);
    if (!ref.read(isPremiumProvider)) {
      _showingSheet = true;
      widget.onSheetVisibilityChanged?.call(true);
      try {
        final unlocked = await PremiumPaywallSheet.show(
          context,
          lockedFeature: appL10n.voicePremiumRequired,
        );
        if (!mounted) return;
        if (unlocked == true && ref.read(isPremiumProvider)) {
          await ref.read(appSettingsProvider.notifier).setVoiceEnabled(true);
        }
      } finally {
        _showingSheet = false;
        if (mounted) widget.onSheetVisibilityChanged?.call(false);
      }
      return;
    }
    if (speed) {
      _showingSheet = true;
      widget.onSheetVisibilityChanged?.call(true);
      try {
        await showVoiceSpeedPicker(context);
      } finally {
        _showingSheet = false;
        if (mounted) widget.onSheetVisibilityChanged?.call(false);
      }
    } else {
      HapticFeedbackHelper.select();
      await ref
          .read(appSettingsProvider.notifier)
          .setVoiceEnabled(!settings.voiceEnabled);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final premium = ref.watch(isPremiumProvider);
    final locked = !premium;
    final enabled = premium && settings.voiceEnabled;
    final colors = AppColors.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final label = locked
        ? appL10n.voicePremium
        : enabled
        ? appL10n.gameVoiceOn
        : appL10n.gameVoiceOff;
    final foreground = locked
        ? colors.premiumAmber
        : enabled
        ? colors.accent
        : colors.secondaryText;
    final background = locked
        ? colors.premiumAmberSurface
        : enabled
        ? colors.accentSurface10
        : colors.cardBackground;
    final canChooseSpeed = premium;
    final speed = voiceSpeedLabel(settings.voiceSpeed);

    return Semantics(
      button: true,
      label: label,
      value: canChooseSpeed ? appL10n.voiceSpeedValue(speed) : null,
      hint: canChooseSpeed ? appL10n.voiceSpeedHint : null,
      toggled: canChooseSpeed ? enabled : null,
      onTap: _interact,
      onLongPress: canChooseSpeed ? () => _interact(speed: true) : null,
      child: Tooltip(
        message: label,
        // Long press belongs to the speed picker; hover still shows the tooltip.
        triggerMode: TooltipTriggerMode.manual,
        child: ExcludeSemantics(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.f10, shift: true): () =>
                  _interact(speed: true),
            },
            child: Listener(
              onPointerDown: (_) => setState(() => _pressed = true),
              onPointerUp: (_) => setState(() => _pressed = false),
              onPointerCancel: (_) => setState(() => _pressed = false),
              child: AnimatedScale(
                scale: _pressed && !reduceMotion ? .95 : 1,
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 100),
                curve: Curves.easeOutCubic,
                child: AnimatedContainer(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  constraints: const BoxConstraints(
                    minHeight: 44,
                    minWidth: 56,
                  ),
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _interact,
                      onLongPress: () => _interact(speed: true),
                      onSecondaryTap: () => _interact(speed: true),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              enabled || locked
                                  ? Icons.record_voice_over_rounded
                                  : Icons.voice_over_off_rounded,
                              size: 20,
                              color: foreground,
                            ),
                            const SizedBox(width: 5),
                            if (locked)
                              Icon(
                                Icons.lock_rounded,
                                size: 13,
                                color: foreground,
                              )
                            else
                              // Fixed width keeps adjacent header content still.
                              SizedBox(
                                width: 29,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '${speed}x',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: foreground,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Also reachable by a regular tap in Settings and by a screen-reader action.
Future<void> showVoiceSpeedPicker(BuildContext context) async {
  HapticFeedbackHelper.tap();
  final colors = AppColors.of(context);
  final container = ProviderScope.containerOf(context);
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.cardBackground,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: BoxConstraints(
      maxWidth: 480,
      maxHeight: MediaQuery.sizeOf(context).height * .9,
    ),
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: Duration(milliseconds: 240),
            reverseDuration: Duration(milliseconds: 180),
          ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => UncontrolledProviderScope(
      container: container,
      child: const _VoiceSpeedPicker(),
    ),
  );
}

class _VoiceSpeedPicker extends ConsumerWidget {
  const _VoiceSpeedPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final premium = ref.watch(isPremiumProvider);
    final allowed = premium;
    final colors = AppColors.of(context);
    final index = AppSettings.voiceSpeeds.indexOf(settings.voiceSpeed);
    void select(int index) {
      if (!ref.read(isPremiumProvider)) return;
      final speed = AppSettings.voiceSpeeds[index];
      if (speed == ref.read(appSettingsProvider).voiceSpeed) return;
      HapticFeedbackHelper.select();
      unawaited(ref.read(appSettingsProvider.notifier).setVoiceSpeed(speed));
    }

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (MediaQuery.textScalerOf(context).scale(20) > 28) ...[
              Row(
                children: [
                  Icon(
                    Icons.record_voice_over_rounded,
                    color: colors.accent,
                    size: 24,
                  ),
                  const Spacer(),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  header: true,
                  child: Text(
                    appL10n.voiceSpeed,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: colors.primaryText,
                    ),
                  ),
                ),
              ),
            ] else
              Row(
                children: [
                  Icon(
                    Icons.record_voice_over_rounded,
                    color: colors.accent,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        appL10n.voiceSpeed,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: colors.primaryText,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                allowed
                    ? appL10n.voiceSpeedDescription
                    : appL10n.voicePremiumRequired,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: colors.secondaryText,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Semantics(
              label: appL10n.voiceSpeed,
              child: Slider(
                key: const ValueKey('voice-speed-slider'),
                value: (index < 0 ? 1 : index).toDouble(),
                min: 0,
                max: 3,
                divisions: 3,
                activeColor: colors.accent,
                inactiveColor: colors.accentSurface10,
                label: '${voiceSpeedLabel(settings.voiceSpeed)}x',
                semanticFormatterCallback: (value) => appL10n.voiceSpeedValue(
                  voiceSpeedLabel(AppSettings.voiceSpeeds[value.round()]),
                ),
                onChanged: allowed ? (value) => select(value.round()) : null,
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < AppSettings.voiceSpeeds.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Semantics(
                        selected: i == index,
                        child: TextButton(
                          key: ValueKey(
                            'voice-speed-${AppSettings.voiceSpeeds[i]}',
                          ),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(44, 44),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 8,
                            ),
                            foregroundColor: i == index
                                ? colors.accent
                                : colors.secondaryText,
                            backgroundColor: i == index
                                ? colors.accentSurface10
                                : Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: allowed ? () => select(i) : null,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '${voiceSpeedLabel(AppSettings.voiceSpeeds[i])}x',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class QuestionVoiceSettingsTile extends ConsumerWidget {
  const QuestionVoiceSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final premium = ref.watch(isPremiumProvider);
    final colors = AppColors.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appL10n.voiceOverQuestions,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      premium
                          ? appL10n.voiceLanguageDescription
                          : appL10n.voicePremium,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const QuestionVoiceToggle(),
            ],
          ),
        ),
        if (premium)
          Material(
            color: colors.cardBackground,
            child: ListTile(
              key: const ValueKey('voice-speed-setting'),
              leading: Icon(Icons.speed_rounded, color: colors.secondaryText),
              title: Text(
                appL10n.voiceSpeed,
                style: const TextStyle(fontSize: 15),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${voiceSpeedLabel(settings.voiceSpeed)}x',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colors.accent,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ),
              onTap: () => showVoiceSpeedPicker(context),
            ),
          ),
      ],
    );
  }
}
