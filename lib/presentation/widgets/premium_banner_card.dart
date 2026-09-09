import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/presentation/widgets/premium_paywall_sheet.dart';
import 'package:pdd_app/presentation/widgets/subscription_management_sheet.dart';

/// Карточка статуса Premium с тремя состояниями светофора:
/// 1. Желтый (#FFA53C): есть бесплатные карточки (1..10)
/// 2. Красный (#ED4621): бесплатные карточки закончились (0 из 10)
/// 3. Зеленый (#2BC280): премиум активен (бейдж «АКТИВЕН» + зеленый светофор)
///
/// Полностью соблюдает единый стиль приложения: плоский дизайн без теней и свечений,
/// стандартные размеры шрифтов Onest и скругления AppDimensions.cardRadius.
class PremiumBannerCard extends ConsumerWidget {
  const PremiumBannerCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPremium = ref.watch(isPremiumProvider);
    final remaining = ref.watch(dailyCardsRemainingProvider);
    final limit = ref.watch(dailyFreeLimitProvider);

    final Color cardColor;
    final String svgAsset;
    final String subtitleText;

    if (isPremium) {
      cardColor = const Color(0xFF2BC280);
      svgAsset = 'assets/images/traffic_light_green.svg';
      subtitleText = 'Умная лента и ИИ без ограничений';
    } else if (remaining > 0) {
      cardColor = const Color(0xFFFFA53C);
      svgAsset = 'assets/images/traffic_light_yellow.svg';
      subtitleText = 'Осталось бесплатных карточек: $remaining из $limit';
    } else {
      cardColor = const Color(0xFFED4621);
      svgAsset = 'assets/images/traffic_light_red.svg';
      subtitleText = 'Осталось бесплатных карточек: 0 из $limit';
    }

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedbackHelper.tap();
              if (isPremium) {
                SubscriptionManagementSheet.show(context);
              } else {
                PremiumPaywallSheet.show(context);
              }
            },
            splashColor: Colors.white.withValues(alpha: 0.15),
            highlightColor: Colors.white.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  // Левая колонка: Заголовок и статус (типографика в едином стиле приложения)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text(
                              'Премиум доступ',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                height: 1.2,
                              ),
                            ),
                            if (isPremium) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'АКТИВЕН',
                                  style: TextStyle(
                                    color: Color(0xFF121212),
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitleText,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w400,
                            color: Colors.white.withValues(alpha: 0.95),
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Правая колонка: Плоский компактный светофор
                  SvgPicture.asset(
                    svgAsset,
                    width: 36,
                    height: 48,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
