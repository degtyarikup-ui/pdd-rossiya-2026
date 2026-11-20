import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/onboarding_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/onboarding/widgets/onboarding_learners_step.dart';
import 'package:pdd_app/presentation/screens/onboarding/widgets/onboarding_personalize_step.dart';
import 'package:pdd_app/presentation/screens/onboarding/widgets/onboarding_plan_ready_step.dart';
import 'package:pdd_app/presentation/screens/onboarding/widgets/onboarding_smart_practice_step.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';
import 'package:pdd_app/presentation/widgets/app_toast.dart';
import 'package:pdd_app/presentation/widgets/premium_benefits_screen.dart';

/// Пятишаговый онбординг первого запуска:
/// 1. Выпускники с правами + подтверждённый рейтинг и процент сдачи
/// 2. Наглядный прогресс по темам и практика без воды
/// 3. Выбор категории (A/B или C/D) и ежедневного темпа
/// 4. Персональный план подготовки и прогноз готовности
/// 5. Экран Премиум-пэйвола с предложением сразу оформить подписку
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onCompleted,
    this.preview = false,
    this.now,
  });

  final VoidCallback onCompleted;
  final bool preview;
  final DateTime? now;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const int _setupSteps = 4;

  int _step = 0;
  late TicketCategory _selectedCategory;
  late OnboardingPace _selectedPace;
  bool _saving = false;
  bool _categoryWritePending = false;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.preview
        ? TicketCategory.ab
        : ref.read(appSettingsProvider).ticketCategory;
    _selectedPace = widget.preview
        ? OnboardingPace.optimal
        : OnboardingService.instance.pace;
  }

  void _goBack() {
    if (_saving || _step <= 0) return;
    HapticFeedbackHelper.tap();
    setState(() => _step--);
  }

  Future<void> _savePlan() async {
    if (widget.preview) return;
    final currentCategory = ref.read(appSettingsProvider).ticketCategory;
    if (_categoryWritePending || currentCategory != _selectedCategory) {
      _categoryWritePending = true;
      await ref
          .read(appSettingsProvider.notifier)
          .setTicketCategory(_selectedCategory);
      _categoryWritePending = false;
    }
    await OnboardingService.instance.complete(pace: _selectedPace);
  }

  Future<void> _goNext(int renderedStep) async {
    if (_saving || _step != renderedStep) return;
    HapticFeedbackHelper.tap();
    if (_step < _setupSteps - 1) {
      setState(() => _step++);
      return;
    }
    // The plan is confirmed here, before the optional Premium offer can leave
    // this page for web sign-in or a payment provider.
    await _saveBefore(() => _step++);
  }

  Future<void> _finishOnboarding() async {
    if (_saving) return;
    HapticFeedbackHelper.select();
    if (_step == _setupSteps) {
      _saving = true;
      widget.onCompleted();
      return;
    }
    await _saveBefore(widget.onCompleted, skip: true);
  }

  Future<void> _saveBefore(VoidCallback onSaved, {bool skip = false}) async {
    setState(() => _saving = true);
    try {
      await _savePlan();
    } catch (error) {
      debugPrint('Onboarding save error: $error');
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(
        context,
        context.l10n.onboardingPlanSaveFailed,
        type: AppToastType.error,
      );
      if (skip) onSaved();
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    onSaved();
  }

  Widget _buildSetupStepContent() {
    return switch (_step) {
      0 => const OnboardingLearnersStep(key: ValueKey('onboarding-step-0')),
      1 => const OnboardingSmartPracticeStep(
        key: ValueKey('onboarding-step-1'),
      ),
      2 => OnboardingPersonalizeStep(
        key: const ValueKey('onboarding-step-2'),
        selectedCategory: _selectedCategory,
        selectedPace: _selectedPace,
        onCategoryChanged: (category) {
          setState(() => _selectedCategory = category);
        },
        onPaceChanged: (pace) {
          setState(() => _selectedPace = pace);
        },
      ),
      _ => OnboardingPlanReadyStep(
        key: const ValueKey('onboarding-step-3'),
        category: _selectedCategory,
        pace: _selectedPace,
        now: widget.now,
      ),
    };
  }

  Widget _buildSetupScaffold(
    BuildContext context, {
    required AppThemeColors colors,
    required AppLocalizations l10n,
    required bool disableAnimations,
  }) {
    final renderedStep = _step;
    final overlayStyle = colors.isDark
        ? SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: colors.background,
          )
        : SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: colors.background,
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      key: const ValueKey('onboarding-setup-shell'),
      value: overlayStyle,
      child: Scaffold(
        key: const ValueKey('onboarding-screen'),
        backgroundColor: colors.background,
        body: Stack(
          children: [
            // Мягкий акцентный градиент в верхней части экрана готового плана.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 280,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _step == 3 ? 1.0 : 0.0,
                  duration: disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 280),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          colors.lightAccent,
                          colors.background.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SafeArea(
                  bottom: false,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: _OnboardingTopBar(
                        step: _step,
                        totalSteps: _setupSteps,
                        disableAnimations: disableAnimations,
                        onBack: _step > 0 ? _goBack : null,
                        onSkip: _finishOnboarding,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    removeBottom: true,
                    child: disableAnimations
                        ? SizedBox.expand(child: _buildSetupStepContent())
                        : AnimatedSwitcher(
                            duration: const Duration(milliseconds: 240),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            layoutBuilder: (currentChild, previousChildren) {
                              return Stack(
                                alignment: Alignment.topCenter,
                                fit: StackFit.expand,
                                children: [
                                  for (final child in previousChildren)
                                    ExcludeSemantics(
                                      child: IgnorePointer(child: child),
                                    ),
                                  ?currentChild,
                                ],
                              );
                            },
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: child,
                              );
                            },
                            child: _buildSetupStepContent(),
                          ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppDimensions.screenPadding,
                          AppDimensions.spacingM,
                          AppDimensions.screenPadding,
                          AppDimensions.spacingL,
                        ),
                        child: SizedBox(
                          height: 56,
                          width: double.infinity,
                          child: ElevatedButton(
                            key: const ValueKey('onboarding-primary-cta'),
                            onPressed: _saving
                                ? null
                                : () => _goNext(renderedStep),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color.lerp(
                                colors.accent,
                                colors.black,
                                0.17,
                              ),
                              foregroundColor: colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppDimensions.buttonRadius,
                                ),
                              ),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                l10n.onboardingContinue,
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appColors = AppColors.of(context);
    final colors = appColors.isDark
        ? appColors
        : appColors.copyWith(
            secondaryText: Color.lerp(
              appColors.secondaryText,
              appColors.primaryText,
              0.42,
            ),
          );
    final l10n = context.l10n;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    final Widget activeScreen = _step == _setupSteps
        ? PremiumBenefitsScreen(
            key: const ValueKey('onboarding-step-4'),
            fromOnboarding: true,
            onDismissed: (_) => _finishOnboarding(),
            onBack: _goBack,
            dismissLabel: l10n.onboardingContinueFree,
          )
        : Theme(
            data: theme.copyWith(
              extensions: [...theme.extensions.values, colors],
            ),
            child: _buildSetupScaffold(
              context,
              colors: colors,
              l10n: l10n,
              disableAnimations: disableAnimations,
            ),
          );

    return PopScope(
      canPop: _step == 0 && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0) {
          _goBack();
        }
      },
      child: disableAnimations
          ? activeScreen
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.center,
                children: [
                  for (final child in previousChildren)
                    ExcludeSemantics(child: IgnorePointer(child: child)),
                  ?currentChild,
                ],
              ),
              child: activeScreen,
            ),
    );
  }
}

class _OnboardingTopBar extends StatelessWidget {
  const _OnboardingTopBar({
    required this.step,
    required this.totalSteps,
    required this.disableAnimations,
    this.onBack,
    this.onSkip,
  });

  final int step;
  final int totalSteps;
  final bool disableAnimations;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final progress = ((step + 1) / totalSteps).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxSkipWidth = math.max(
          72.0,
          (constraints.maxWidth - AppDimensions.screenPadding * 2) * 0.36,
        );

        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDimensions.screenPadding,
            8,
            AppDimensions.screenPadding,
            8,
          ),
          child: SizedBox(
            height: 40,
            child: Row(
              children: [
                if (onBack != null)
                  Tooltip(
                    message: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    child: AppChromeIconButton(
                      key: const ValueKey('onboarding-back'),
                      icon: Icons.arrow_back_ios_new_rounded,
                      onTap: onBack,
                    ),
                  )
                else
                  const SizedBox(width: 40, height: 40),
                const SizedBox(width: AppDimensions.spacingM),
                Expanded(
                  child: step == 0
                      ? const SizedBox.shrink()
                      : Semantics(
                          label: l10n.onboardingStepSemantics(
                            step + 1,
                            totalSteps,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 220),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: SizedBox(
                                  height: 8,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      ColoredBox(color: colors.gray),
                                      AnimatedFractionallySizedBox(
                                        alignment: Alignment.centerLeft,
                                        widthFactor: progress,
                                        duration: disableAnimations
                                            ? Duration.zero
                                            : const Duration(milliseconds: 260),
                                        curve: Curves.easeOutCubic,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: colors.accent,
                                            borderRadius: BorderRadius.circular(
                                              999,
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
                const SizedBox(width: AppDimensions.spacingM),
                if (onSkip != null)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: 40,
                      maxWidth: maxSkipWidth,
                    ),
                    child: TextButton(
                      key: const ValueKey('onboarding-skip'),
                      onPressed: onSkip,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.secondaryText,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        minimumSize: const Size(40, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          l10n.onboardingSkip,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 40, height: 40),
              ],
            ),
          ),
        );
      },
    );
  }
}
