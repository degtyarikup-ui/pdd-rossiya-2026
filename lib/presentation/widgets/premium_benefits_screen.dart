import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/premium_plans_sheet.dart';

/// The benefits stay visible behind the plan picker. Only a completed store
/// purchase/restore or an Android browser handoff closes this route as well.
class PremiumBenefitsScreen extends StatefulWidget {
  const PremiumBenefitsScreen({super.key});

  @override
  State<PremiumBenefitsScreen> createState() => _PremiumBenefitsScreenState();
}

class _PremiumBenefitsScreenState extends State<PremiumBenefitsScreen> {
  bool _showingPlans = false;

  Future<void> _showPlans() async {
    if (_showingPlans) return;
    HapticFeedbackHelper.tap();
    setState(() => _showingPlans = true);
    final result = await PremiumPlansSheet.show(context);
    if (!mounted) return;
    setState(() => _showingPlans = false);
    if (result != null) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.accent,
      ),
      child: Scaffold(
        backgroundColor: AppColors.accent,
        body: SafeArea(
          top: false,
          bottom: false,
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      key: const ValueKey('premium-benefits-scroll'),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 600),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final width = constraints.maxWidth;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _BenefitsHeader(width: width),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      AppDimensions.screenPadding,
                                      36,
                                      AppDimensions.screenPadding,
                                      24,
                                    ),
                                    child: Column(
                                      children: [
                                        _Benefit(
                                          asset: 'feature_games.svg',
                                          title: l10n.premiumBenefitGamesTitle,
                                          detail:
                                              l10n.premiumBenefitGamesDetail,
                                        ),
                                        const SizedBox(height: 24),
                                        _Benefit(
                                          asset: 'feature_ai.svg',
                                          title: l10n.premiumBenefitAiTitle,
                                          detail: l10n.premiumBenefitAiDetail,
                                        ),
                                        const SizedBox(height: 24),
                                        _Benefit(
                                          asset: 'feature_voice.svg',
                                          title: l10n.premiumBenefitVoiceTitle,
                                          detail:
                                              l10n.premiumBenefitVoiceDetail,
                                          voiceIcon: true,
                                        ),
                                        const SizedBox(height: 24),
                                        _Benefit(
                                          asset: 'feature_feed.svg',
                                          title: l10n.premiumBenefitFeedTitle,
                                          detail: l10n.premiumBenefitFeedDetail,
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
                  SafeArea(
                    top: false,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppDimensions.screenPadding,
                            12,
                            AppDimensions.screenPadding,
                            12,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ElevatedButton(
                                key: const ValueKey('premium-show-plans'),
                                onPressed: _showingPlans ? null : _showPlans,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.white,
                                  foregroundColor: AppColors.accent,
                                  disabledBackgroundColor: AppColors.white,
                                  disabledForegroundColor: AppColors.accent,
                                  minimumSize: const Size.fromHeight(56),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 16,
                                  ),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppDimensions.buttonRadius,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  l10n.paywallSubscribe,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                l10n.paywallFreeNote,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.3,
                                  color: AppColors.white.withValues(alpha: .85),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 12,
                left: math.max(
                  AppDimensions.screenPadding,
                  (MediaQuery.sizeOf(context).width - 600) / 2 +
                      AppDimensions.screenPadding,
                ),
                child: IconButton(
                  key: const ValueKey('premium-close-benefits'),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primaryText,
                    foregroundColor: AppColors.white,
                    minimumSize: const Size.square(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppDimensions.buttonRadius,
                      ),
                    ),
                  ),
                  icon: SvgPicture.asset(
                    'assets/images/premium/close.svg',
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BenefitsHeader extends StatelessWidget {
  const _BenefitsHeader({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    // Align the photo and gradient edge to physical pixels to avoid a thin
    // uncovered image seam at fractional layout heights.
    final imageHeight = (width * 380 / 576 * pixelRatio).ceil() / pixelRatio;
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
    final headlineStyle = TextStyle(
      fontSize: largeText
          ? (width / 16).clamp(20, 28)
          : (width / 12).clamp(28, 44),
      fontWeight: FontWeight.w800,
      color: AppColors.white,
      height: 1.05,
      letterSpacing: -.5,
    );
    // Display headings may wrap between words, but should not split a long
    // localized word at accessibility sizes. All body text scales normally.
    final wordPainter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    );
    var widestWord = 0.0;
    for (final word in l10n.paywallTitle.split(RegExp(r'\s+'))) {
      wordPainter.text = TextSpan(
        text: word,
        style: DefaultTextStyle.of(context).style.merge(headlineStyle),
      );
      wordPainter.layout();
      widestWord = math.max(widestWord, wordPainter.width);
    }
    wordPainter.dispose();
    final availableWidth = width - AppDimensions.screenPadding * 2;
    final fontSize = widestWord > availableWidth
        ? headlineStyle.fontSize! * availableWidth / widestWord * .98
        : headlineStyle.fontSize!;
    final rating = _ProofPoint(
      value: l10n.premiumRatingValue,
      label: l10n.premiumRatingLabel,
      leftAsset: 'laurel_left.svg',
      rightAsset: 'laurel_right.svg',
      star: true,
    );
    final passRate = _ProofPoint(
      value: l10n.premiumPassRateValue,
      label: l10n.premiumPassRateLabel,
      leftAsset: 'laurel_pass_left.svg',
      rightAsset: 'laurel_pass_right.svg',
    );
    return Stack(
      children: [
        SizedBox(
          height: imageHeight,
          width: width,
          child: ExcludeSemantics(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/images/premium/hero.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.bottomCenter,
                  cacheWidth: (width * MediaQuery.devicePixelRatioOf(context))
                      .ceil()
                      .clamp(1, 1024),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, .57, .98],
                      colors: [
                        Color(0x000574F8),
                        Color(0x000574F8),
                        AppColors.accent,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            AppDimensions.screenPadding,
            imageHeight - 20,
            AppDimensions.screenPadding,
            0,
          ),
          child: Column(
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.paywallTitle,
                  textAlign: TextAlign.center,
                  style: headlineStyle.copyWith(fontSize: fontSize),
                ),
              ),
              const SizedBox(height: 28),
              if (largeText)
                Column(children: [rating, const SizedBox(height: 16), passRate])
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: rating),
                    const SizedBox(width: 16),
                    Expanded(child: passRate),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProofPoint extends StatelessWidget {
  const _ProofPoint({
    required this.value,
    required this.label,
    required this.leftAsset,
    required this.rightAsset,
    this.star = false,
  });

  final String value;
  final String label;
  final String leftAsset;
  final String rightAsset;
  final bool star;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$value, $label',
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // At large accessibility sizes the factual text takes priority over
          // decoration, without shrinking or truncating either statistic.
          final showLaurels =
              constraints.maxWidth >= 150 &&
              MediaQuery.textScalerOf(context).scale(14) <= 18;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showLaurels)
                SizedBox(
                  width: 22,
                  height: 54,
                  child: SvgPicture.asset('assets/images/premium/$leftAsset'),
                ),
              Expanded(
                child: Column(
                  children: [
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 4,
                      children: [
                        if (star)
                          SvgPicture.asset('assets/images/premium/star.svg'),
                        Text(
                          value,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: AppColors.white,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.2,
                        color: AppColors.white.withValues(alpha: .8),
                      ),
                    ),
                  ],
                ),
              ),
              if (showLaurels)
                SizedBox(
                  width: 22,
                  height: 54,
                  child: SvgPicture.asset('assets/images/premium/$rightAsset'),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({
    required this.asset,
    required this.title,
    required this.detail,
    this.voiceIcon = false,
  });

  final String asset;
  final String title;
  final String detail;
  final bool voiceIcon;

  @override
  Widget build(BuildContext context) {
    final icon = SvgPicture.asset(
      'assets/images/premium/$asset',
      excludeFromSemantics: true,
    );
    return Row(
      children: [
        SizedBox.square(
          dimension: 56,
          child: voiceIcon
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.white.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(
                      AppDimensions.cardRadius,
                    ),
                  ),
                  child: Center(child: icon),
                )
              : icon,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.white,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.white.withValues(alpha: .8),
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
