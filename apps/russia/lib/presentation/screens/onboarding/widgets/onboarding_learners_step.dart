import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/config/country_config.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Экран 1 онбординга: живая двухрядная мозаика выпускников с российскими
/// правами + подтверждённые показатели рейтинга и сдачи.
class OnboardingLearnersStep extends StatefulWidget {
  const OnboardingLearnersStep({super.key});

  @override
  State<OnboardingLearnersStep> createState() => _OnboardingLearnersStepState();
}

class _OnboardingLearnersStepState extends State<OnboardingLearnersStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 780),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _entrance,
    curve: Curves.easeOutCubic,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _started = true;
      _entrance.value = 1;
    } else if (!_started) {
      _started = true;
      _entrance.forward();
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final l10n = context.l10n;
    final config = CountryConfig.current;
    final photos = config.onboardingLearnerPhotos;
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final largeText = textScale > 1.3;

    // Порядок в рядах подобран так, чтобы уже в первом кадре сохранялся
    // естественный баланс ~70% девушек и ~30% парней и разные ракурсы/свет.
    final row1 = <String>[
      if (photos.isNotEmpty) photos[0],
      if (photos.length > 1) photos[1],
      if (photos.length > 3) photos[3],
      if (photos.length > 2) photos[2],
      if (photos.length > 4) photos[4],
    ];
    final row2 = <String>[
      if (photos.length > 7) photos[7],
      if (photos.length > 5) photos[5],
      if (photos.length > 9) photos[9],
      if (photos.length > 6) photos[6],
      if (photos.length > 8) photos[8],
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final singleRow = availableHeight < 500 || textScale > 1.65;
        final rowGap = (availableHeight * 0.018).clamp(10.0, 15.0);
        final double cardHeight = singleRow
            ? math.min(172.0, math.max(118.0, availableHeight * 0.30))
            : ((availableHeight - 266) / 2).clamp(138.0, 250.0);
        final double cardWidth = (cardHeight * 0.77).roundToDouble();
        final topInset = (availableHeight * 0.014).clamp(4.0, 14.0);
        final mosaicToStatsGap = (availableHeight * 0.042).clamp(20.0, 34.0);
        final statsToTitleGap = (availableHeight * 0.032).clamp(18.0, 26.0);
        final bottomInset = (availableHeight * 0.028).clamp(14.0, 26.0);

        return SingleChildScrollView(
          key: const ValueKey('onboarding-step-0-scroll'),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: availableHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: topInset),
                  child: ExcludeSemantics(
                    child: AnimatedBuilder(
                      animation: _curve,
                      builder: (context, _) {
                        final t = _curve.value;
                        return Opacity(
                          opacity: (0.35 + 0.65 * t).clamp(0.0, 1.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Transform.translate(
                                offset: Offset(18 * (1 - t), 0),
                                child: _PhotoStrip(
                                  photos: singleRow ? [...row1, ...row2] : row1,
                                  cardWidth: cardWidth,
                                  cardHeight: cardHeight,
                                  leadingInset: AppDimensions.screenPadding,
                                  initialOffset: 0,
                                ),
                              ),
                              if (!singleRow && row2.isNotEmpty) ...[
                                SizedBox(height: rowGap),
                                Transform.translate(
                                  offset: Offset(-18 * (1 - t), 0),
                                  child: _PhotoStrip(
                                    photos: row2,
                                    cardWidth: cardWidth,
                                    cardHeight: cardHeight,
                                    leadingInset: 14,
                                    initialOffset: (cardWidth * 0.44)
                                        .roundToDouble(),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppDimensions.screenPadding,
                        mosaicToStatsGap,
                        AppDimensions.screenPadding,
                        bottomInset,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _LaurelStatsRow(
                            largeText: largeText || constraints.maxWidth < 340,
                          ),
                          SizedBox(height: statsToTitleGap),
                          Semantics(
                            header: true,
                            child: Text(
                              l10n.onboardingHeroTitle(config.examOfficeName),
                              style: TextStyle(
                                fontSize: largeText ? 24 : 30,
                                fontWeight: FontWeight.w800,
                                height: 1.12,
                                letterSpacing: -0.5,
                                color: colors.primaryText,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            l10n.onboardingHeroSubtitle(
                              config.questionsPerCategory,
                            ),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                              height: 1.38,
                              color: colors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PhotoStrip extends StatefulWidget {
  const _PhotoStrip({
    required this.photos,
    required this.cardWidth,
    required this.cardHeight,
    required this.leadingInset,
    required this.initialOffset,
  });

  final List<String> photos;
  final double cardWidth;
  final double cardHeight;
  final double leadingInset;
  final double initialOffset;

  @override
  State<_PhotoStrip> createState() => _PhotoStripState();
}

class _PhotoStripState extends State<_PhotoStrip> {
  late final ScrollController _scrollController = ScrollController(
    initialScrollOffset: widget.initialOffset,
  );

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return SizedBox(
      height: widget.cardHeight,
      child: ListView.separated(
        controller: _scrollController,
        shrinkWrap: true,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.only(
          left: widget.leadingInset,
          right: AppDimensions.screenPadding,
        ),
        itemCount: widget.photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final asset = widget.photos[index];
          return ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: widget.cardWidth,
              height: widget.cardHeight,
              color: colors.gray,
              child: Image.asset(
                asset,
                width: widget.cardWidth,
                height: widget.cardHeight,
                fit: BoxFit.cover,
                alignment: const Alignment(0, -0.2),
                errorBuilder: (_, _, _) => Center(
                  child: Icon(
                    Icons.badge_outlined,
                    color: colors.secondaryText,
                    size: 28,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LaurelStatsRow extends StatelessWidget {
  const _LaurelStatsRow({required this.largeText});

  final bool largeText;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);

    final ratingBadge = _LaurelProofBadge(
      value: l10n.premiumRatingValue,
      label: l10n.premiumRatingLabel,
      leftAsset: 'laurel_left.svg',
      rightAsset: 'laurel_right.svg',
      leadingIcon: Icon(Icons.verified_rounded, size: 22, color: colors.green),
    );

    final passBadge = _LaurelProofBadge(
      value: l10n.premiumPassRateValue,
      label: l10n.premiumPassRateLabel,
      leftAsset: 'laurel_pass_left.svg',
      rightAsset: 'laurel_pass_right.svg',
    );

    if (largeText) {
      return Column(
        children: [
          ratingBadge,
          const SizedBox(height: AppDimensions.spacingM),
          passBadge,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: ratingBadge),
        const SizedBox(width: AppDimensions.spacingM),
        Expanded(child: passBadge),
      ],
    );
  }
}

class _LaurelProofBadge extends StatelessWidget {
  const _LaurelProofBadge({
    required this.value,
    required this.label,
    required this.leftAsset,
    required this.rightAsset,
    this.leadingIcon,
  });

  final String value;
  final String label;
  final String leftAsset;
  final String rightAsset;
  final Widget? leadingIcon;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final showLaurels = MediaQuery.textScalerOf(context).scale(14) <= 18;
    final laurelFilter = ColorFilter.mode(
      colors.secondaryText.withValues(alpha: 0.72),
      BlendMode.srcIn,
    );

    return Semantics(
      label: '$value, $label',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (showLaurels)
            SizedBox(
              width: 18,
              height: 52,
              child: SvgPicture.asset(
                'assets/images/premium/$leftAsset',
                colorFilter: laurelFilter,
              ),
            ),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 5,
                    children: [
                      ?leadingIcon,
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                          letterSpacing: -0.4,
                          color: colors.primaryText,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                      color: colors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (showLaurels)
            SizedBox(
              width: 18,
              height: 52,
              child: SvgPicture.asset(
                'assets/images/premium/$rightAsset',
                colorFilter: laurelFilter,
              ),
            ),
        ],
      ),
    );
  }
}
