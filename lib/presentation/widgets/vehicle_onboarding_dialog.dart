import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/ticket_category.dart';
import 'package:pdd_app/data/repositories/providers.dart';

/// Показывает онбординг выбора категории билетов при первом запуске.
Future<void> showVehicleOnboardingIfNeeded(
  BuildContext context,
  WidgetRef ref,
) async {
  await ref.read(appSettingsProvider.notifier).ready;
  if (!context.mounted) return;
  if (ref.read(appSettingsProvider).vehicleOnboardingCompleted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => VehicleOnboardingDialog(ref: ref),
  );
}

void _invalidateCategoryDependents(WidgetRef ref) {
  ref.invalidate(ticketsProvider);
  ref.invalidate(topicsProvider);
  ref.invalidate(statsProvider);
  ref.invalidate(ticketProgressProvider);
  ref.invalidate(favoriteQuestionsProvider);
  ref.invalidate(wrongQuestionIdsProvider);
  ref.read(appDataRefreshProvider.notifier).state++;
}

class VehicleOnboardingDialog extends StatelessWidget {
  const VehicleOnboardingDialog({super.key, required this.ref});

  final WidgetRef ref;

  Future<void> _choose(BuildContext context, TicketCategory category) async {
    HapticFeedbackHelper.select();
    await ref.read(appSettingsProvider.notifier).finishVehicleOnboarding(category);
    _invalidateCategoryDependents(ref);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.screenPadding,
        vertical: 24,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppDimensions.spacingL),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'На чем планируешь ездить?',
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.primaryText,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingL),
            _OnboardingOptionCard(
              title: 'A/B',
              subtitle: 'Автомобиль, мотоцикл',
              icon: Icons.directions_car_rounded,
              onTap: () => _choose(context, TicketCategory.ab),
            ),
            const SizedBox(height: AppDimensions.spacingM),
            _OnboardingOptionCard(
              title: 'C/D',
              subtitle: 'Грузовик, автобус',
              icon: Icons.local_shipping_rounded,
              onTap: () => _choose(context, TicketCategory.cd),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingOptionCard extends StatelessWidget {
  const _OnboardingOptionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.lightAccent,
      borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimensions.buttonRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.spacingL,
            vertical: AppDimensions.spacingM,
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 28,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: AppDimensions.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: AppColors.accent,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryText,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.secondaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
