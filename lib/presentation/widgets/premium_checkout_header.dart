import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/premium_banner_card.dart';

/// Progress follows verified account/payment state; upcoming stages cannot be
/// opened by tapping their labels. The completed sign-in stage allows going back.
class PremiumCheckoutHeader extends StatelessWidget {
  const PremiumCheckoutHeader({
    super.key,
    required this.stage,
    required this.title,
    this.subtitle,
    this.onAccountTap,
  });

  final int stage;
  final String title;
  final String? subtitle;
  final VoidCallback? onAccountTap;

  @override
  Widget build(BuildContext context) {
    final complete = stage == 2;
    final foreground = complete ? AppColors.primaryText : AppColors.white;
    final labels = [
      appL10n.checkoutTabAccount,
      appL10n.checkoutTabPayment,
      appL10n.checkoutTabDone,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final expandedText = MediaQuery.textScalerOf(context).scale(16) > 22;
        final showArtwork = constraints.maxWidth >= 350 && !expandedText;
        final artSlot = constraints.maxWidth >= 500 ? 180.0 : 120.0;
        final artWidth = (artSlot + 16) * 2;
        final pageGutter =
            (MediaQuery.sizeOf(context).width - constraints.maxWidth) / 2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SvgPicture.asset(
                            'assets/images/premium/verified_${complete ? 'lime' : 'blue'}.svg',
                            width: 20,
                            height: 20,
                            excludeFromSemantics: true,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              appL10n.premiumAccessTitle,
                              style: TextStyle(
                                color: foreground,
                                fontSize: 15,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Semantics(
                        header: true,
                        liveRegion: true,
                        child: Text(
                          title,
                          key: const ValueKey('checkout-stage-title'),
                          style: TextStyle(
                            color: foreground,
                            fontSize: constraints.maxWidth >= 500 ? 34 : 28,
                            height: 1.12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            color: foreground.withValues(alpha: .9),
                            fontSize: 16,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (showArtwork)
                  SizedBox(
                    width: artSlot,
                    height: artWidth * .52,
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: artWidth,
                      maxWidth: artWidth,
                      minHeight: artWidth * .52,
                      maxHeight: artWidth * .52,
                      child: Transform.translate(
                        // The viewport, not an inner box, crops half the car.
                        offset: Offset(pageGutter + artSlot - artWidth / 2, 0),
                        child: ExcludeSemantics(
                          child: IgnorePointer(
                            child: PremiumBannerArtwork(
                              isPremium: complete,
                              contained: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: foreground.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < labels.length; i++)
                    Expanded(
                      child: Semantics(
                        key: ValueKey('checkout-stage-$i'),
                        selected: i == stage,
                        button: i == 0 && stage > 0,
                        enabled: i == 0 && stage > 0
                            ? onAccountTap != null
                            : null,
                        onTap: i == 0 && stage > 0 ? onAccountTap : null,
                        label: appL10n.checkoutStageLabel(i + 1, labels[i]),
                        value: i < stage
                            ? appL10n.checkoutStageCompleted
                            : null,
                        excludeSemantics: true,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: i == 0 && stage > 0 ? onAccountTap : null,
                            borderRadius: BorderRadius.circular(
                              AppDimensions.buttonRadius,
                            ),
                            child: AnimatedContainer(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 220),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: i == stage
                                    ? complete
                                          ? AppColors.white
                                          : AppColors.premiumLime
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(
                                  AppDimensions.buttonRadius,
                                ),
                              ),
                              child: LayoutBuilder(
                                builder: (context, tabConstraints) {
                                  final color = i == stage
                                      ? AppColors.primaryText
                                      : foreground.withValues(
                                          alpha: i < stage ? 1 : .8,
                                        );
                                  final marker = i < stage
                                      ? Icon(
                                          Icons.check_rounded,
                                          size: 18,
                                          color: color,
                                        )
                                      : Text(
                                          '${i + 1}',
                                          style: TextStyle(
                                            color: color,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        );
                                  final label = Text(
                                    labels[i],
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 14,
                                      height: 1.25,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  );
                                  if (tabConstraints.maxWidth < 95 ||
                                      expandedText) {
                                    return Column(
                                      children: [
                                        marker,
                                        const SizedBox(height: 6),
                                        label,
                                      ],
                                    );
                                  }
                                  return Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      marker,
                                      const SizedBox(width: 8),
                                      Flexible(child: label),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
