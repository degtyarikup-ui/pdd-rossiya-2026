import 'package:flutter/material.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/services/onboarding_service.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Экран 3 онбординга: выбор категории прав и темпа занятий.
class OnboardingPersonalizeStep extends StatelessWidget {
  const OnboardingPersonalizeStep({
    super.key,
    required this.selectedCategory,
    required this.selectedPace,
    required this.onCategoryChanged,
    required this.onPaceChanged,
  });

  final TicketCategory selectedCategory;
  final OnboardingPace selectedPace;
  final ValueChanged<TicketCategory> onCategoryChanged;
  final ValueChanged<OnboardingPace> onPaceChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final config = CountryConfig.current;
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final largeText = textScale > 1.3;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final stackCategories = largeText || constraints.maxWidth < 360;
        final stackPaceLabels = largeText || constraints.maxWidth < 340;
        final topPad = (availableHeight * 0.022).clamp(10.0, 18.0);
        final sectionGap = (availableHeight * 0.042).clamp(20.0, 34.0);
        final vehicleHeight = (availableHeight * 0.132).clamp(64.0, 102.0);
        final vehicleGap = (availableHeight * 0.03).clamp(10.0, 24.0);
        final paceVerticalPad = (availableHeight * 0.03).clamp(16.0, 24.0);
        final paceGap = (availableHeight * 0.02).clamp(10.0, 16.0);

        final abCard = _CategoryChoiceCard(
          key: const ValueKey('onboarding-category-ab'),
          title: l10n.onboardingCategoryAbTitle,
          subtitle: l10n.onboardingCategoryAbSubtitle,
          imageAsset: 'assets/images/onboarding_car.png',
          selected: selectedCategory == TicketCategory.ab,
          compactHorizontal: stackCategories,
          vehicleHeight: vehicleHeight,
          vehicleGap: vehicleGap,
          onTap: () {
            HapticFeedbackHelper.select();
            onCategoryChanged(TicketCategory.ab);
          },
        );

        final cdCard = _CategoryChoiceCard(
          key: const ValueKey('onboarding-category-cd'),
          title: l10n.onboardingCategoryCdTitle,
          subtitle: l10n.onboardingCategoryCdSubtitle,
          imageAsset: 'assets/images/onboarding_truck.png',
          selected: selectedCategory == TicketCategory.cd,
          compactHorizontal: stackCategories,
          vehicleHeight: vehicleHeight,
          vehicleGap: vehicleGap,
          onTap: () {
            HapticFeedbackHelper.select();
            onCategoryChanged(TicketCategory.cd);
          },
        );

        return SingleChildScrollView(
          key: const ValueKey('onboarding-step-2-scroll'),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppDimensions.screenPadding,
                  topPad,
                  AppDimensions.screenPadding,
                  AppDimensions.spacingXL,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        config.hasCdCategory
                            ? l10n.onboardingSetupTitle
                            : l10n.onboardingSetupPaceOnlyTitle,
                        style: TextStyle(
                          fontSize: largeText ? 24 : 30,
                          fontWeight: FontWeight.w800,
                          height: 1.12,
                          letterSpacing: -0.5,
                          color: colors.primaryText,
                        ),
                      ),
                    ),
                    if (config.hasCdCategory) ...[
                      SizedBox(height: sectionGap),
                      Text(
                        l10n.onboardingCategorySection,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: colors.secondaryText,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (stackCategories) ...[
                        abCard,
                        SizedBox(height: paceGap),
                        cdCard,
                      ] else
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: abCard),
                              const SizedBox(width: 14),
                              Expanded(child: cdCard),
                            ],
                          ),
                        ),
                    ],
                    SizedBox(height: sectionGap),
                    Text(
                      l10n.onboardingPaceSection,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: colors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _PaceOptionTile(
                      key: const ValueKey('onboarding-pace-10'),
                      title: l10n.onboardingPaceMinutes(10),
                      durationLabel: l10n.onboardingPaceCalmSub,
                      stackLabels: stackPaceLabels,
                      verticalPadding: paceVerticalPad,
                      selected: selectedPace == OnboardingPace.calm,
                      onTap: () {
                        HapticFeedbackHelper.select();
                        onPaceChanged(OnboardingPace.calm);
                      },
                    ),
                    SizedBox(height: paceGap),
                    _PaceOptionTile(
                      key: const ValueKey('onboarding-pace-15'),
                      title: l10n.onboardingPaceMinutes(15),
                      durationLabel: l10n.onboardingPaceOptimalSub,
                      stackLabels: stackPaceLabels,
                      verticalPadding: paceVerticalPad,
                      selected: selectedPace == OnboardingPace.optimal,
                      onTap: () {
                        HapticFeedbackHelper.select();
                        onPaceChanged(OnboardingPace.optimal);
                      },
                    ),
                    SizedBox(height: paceGap),
                    _PaceOptionTile(
                      key: const ValueKey('onboarding-pace-30'),
                      title: l10n.onboardingPaceMinutes(30),
                      durationLabel: l10n.onboardingPaceIntensiveSub,
                      stackLabels: stackPaceLabels,
                      verticalPadding: paceVerticalPad,
                      selected: selectedPace == OnboardingPace.intensive,
                      onTap: () {
                        HapticFeedbackHelper.select();
                        onPaceChanged(OnboardingPace.intensive);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CategoryChoiceCard extends StatelessWidget {
  const _CategoryChoiceCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.imageAsset,
    required this.selected,
    required this.compactHorizontal,
    required this.vehicleHeight,
    required this.vehicleGap,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String imageAsset;
  final bool selected;
  final bool compactHorizontal;
  final double vehicleHeight;
  final double vehicleGap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    const radius = 20.0;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? colors.lightAccent : colors.cardBackground,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: selected ? colors.accent : colors.divider,
                width: selected ? 2 : 1,
              ),
            ),
            child: compactHorizontal
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: colors.primaryText,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: colors.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ExcludeSemantics(
                          child: Image.asset(
                            imageAsset,
                            width: 80,
                            height: 52,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 23,
                          color: selected
                              ? colors.accent
                              : colors.secondaryText,
                        ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 14, 0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      height: 1.15,
                                      color: colors.primaryText,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    subtitle,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      height: 1.25,
                                      color: colors.secondaryText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              selected
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 23,
                              color: selected
                                  ? colors.accent
                                  : colors.secondaryText,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: vehicleGap),
                      Padding(
                        padding: const EdgeInsets.only(left: 16, bottom: 10),
                        child: Align(
                          alignment: Alignment.bottomRight,
                          child: ExcludeSemantics(
                            child: Image.asset(
                              imageAsset,
                              height: vehicleHeight,
                              fit: BoxFit.contain,
                              alignment: Alignment.bottomRight,
                              errorBuilder: (_, _, _) =>
                                  SizedBox(height: vehicleHeight),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _PaceOptionTile extends StatelessWidget {
  const _PaceOptionTile({
    super.key,
    required this.title,
    required this.durationLabel,
    required this.stackLabels,
    required this.verticalPadding,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String durationLabel;
  final bool stackLabels;
  final double verticalPadding;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    const radius = 18.0;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? colors.lightAccent : colors.cardBackground,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: selected ? colors.accent : colors.divider,
                width: selected ? 2 : 1,
              ),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: 18,
              vertical: verticalPadding,
            ),
            child: Row(
              children: [
                if (stackLabels)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                            color: colors.primaryText,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          durationLabel,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: colors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                        color: colors.primaryText,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppDimensions.spacingS),
                  Text(
                    durationLabel,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: colors.secondaryText,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
                const SizedBox(width: 12),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 23,
                  color: selected ? colors.accent : colors.secondaryText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
