import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/presentation/widgets/premium_motion.dart';

/// Shared accessible plan choice for the app paywall and dedicated web checkout.
class PremiumPlanCard extends StatelessWidget {
  const PremiumPlanCard({
    super.key,
    required this.title,
    required this.price,
    required this.selected,
    this.period,
    this.badge,
    this.onTap,
  });

  final String title;
  final String? price;
  final bool selected;
  final String? period;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final priceStyle = TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      height: 1.25,
      color: colors.primaryText,
    );

    Widget details() => Wrap(
      spacing: AppDimensions.spacingS,
      runSpacing: AppDimensions.spacingS,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 17,
            height: 1.25,
            fontWeight: FontWeight.w600,
            color: colors.primaryText,
          ),
        ),
        if (badge != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.premiumLime,
              borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
            ),
            child: Text(
              badge!,
              style: const TextStyle(
                fontSize: 11,
                height: 1.15,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryText,
              ),
            ),
          ),
      ],
    );

    Widget priceLabel({required bool stacked}) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: stacked
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          layoutBuilder: (current, previous) => Stack(
            alignment: stacked ? Alignment.centerLeft : Alignment.centerRight,
            children: [...previous, ?current],
          ),
          child: price == null
              ? ExcludeSemantics(
                  child: DecoratedBox(
                    key: const ValueKey('price-placeholder'),
                    decoration: BoxDecoration(
                      color: colors.primaryText.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '000,00 ₽',
                      style: priceStyle.copyWith(color: Colors.transparent),
                    ),
                  ),
                )
              : Text(
                  price!,
                  key: ValueKey(price),
                  style: priceStyle,
                  textAlign: stacked ? TextAlign.start : TextAlign.end,
                ),
        ),
        if (period != null) ...[
          const SizedBox(height: 3),
          Text(
            period!,
            textAlign: stacked ? TextAlign.start : TextAlign.end,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: colors.primaryText.withValues(alpha: 0.65),
            ),
          ),
        ],
      ],
    );

    return Semantics(
      selected: selected,
      child: PremiumPressFeedback(
        enabled: onTap != null,
        pressedScale: .992,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: selected ? colors.lightAccent : colors.cardBackground,
            borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
            border: Border.all(
              color: selected ? colors.accent : colors.divider,
              width: selected ? 2 : 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(AppDimensions.spacingL),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked =
                        constraints.maxWidth < 300 ||
                        MediaQuery.textScalerOf(context).scale(16) > 20;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          selected
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          color: selected
                              ? colors.accent
                              : colors.secondaryText,
                          size: 22,
                        ),
                        const SizedBox(width: AppDimensions.spacingM),
                        Expanded(
                          child: stacked
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    details(),
                                    const SizedBox(
                                      height: AppDimensions.spacingS,
                                    ),
                                    priceLabel(stacked: true),
                                  ],
                                )
                              : Row(
                                  children: [
                                    Expanded(child: details()),
                                    const SizedBox(
                                      width: AppDimensions.spacingM,
                                    ),
                                    ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: constraints.maxWidth * 0.45,
                                      ),
                                      child: priceLabel(stacked: false),
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
