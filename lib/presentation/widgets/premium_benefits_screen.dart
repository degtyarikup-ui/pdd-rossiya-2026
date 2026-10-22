import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';
import 'package:pdd_app/presentation/widgets/premium_plans_sheet.dart';
import 'package:pdd_app/presentation/widgets/premium_motion.dart';

/// The benefits stay visible behind the plan picker. Only a completed store
/// purchase/restore or an Android browser handoff closes this route as well.
class PremiumBenefitsScreen extends StatefulWidget {
  const PremiumBenefitsScreen({super.key});

  @override
  State<PremiumBenefitsScreen> createState() => _PremiumBenefitsScreenState();
}

class _PremiumBenefitsScreenState extends State<PremiumBenefitsScreen>
    with SingleTickerProviderStateMixin {
  bool _showingPlans = false;
  bool _entranceStarted = false;
  late final AnimationController _timeline = AnimationController(
    vsync: this,
    duration: PremiumMotion.statistics,
  );
  late final Animation<double> _entrance = _timeline.drive(
    CurveTween(
      curve: Interval(
        0,
        PremiumMotion.entrance.inMilliseconds /
            PremiumMotion.statistics.inMilliseconds,
      ),
    ),
  );
  late final Animation<double> _statistics = _timeline.drive(
    CurveTween(curve: const Interval(.08, 1, curve: Curves.easeOutCubic)),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _entranceStarted = true;
      _timeline.value = 1;
    } else if (!_entranceStarted) {
      _entranceStarted = true;
      _timeline.forward();
    }
  }

  @override
  void dispose() {
    _timeline.dispose();
    super.dispose();
  }

  Future<void> _showPlans() async {
    if (_showingPlans) return;
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
                                  _BenefitsHeader(
                                    width: width,
                                    entrance: _entrance,
                                    statistics: _statistics,
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      AppDimensions.screenPadding,
                                      46,
                                      AppDimensions.screenPadding,
                                      24,
                                    ),
                                    child: Column(
                                      children: [
                                        PremiumReveal(
                                          key: const ValueKey(
                                            'premium-reveal-games',
                                          ),
                                          progress: _entrance,
                                          begin: 0.16,
                                          end: 0.56,
                                          child: _Benefit(
                                            asset: 'feature_games.svg',
                                            title:
                                                l10n.premiumBenefitGamesTitle,
                                            inlineDetail: true,
                                            detail:
                                                l10n.premiumBenefitGamesDetail,
                                          ),
                                        ),
                                        const SizedBox(height: 24),
                                        PremiumReveal(
                                          key: const ValueKey(
                                            'premium-reveal-ai',
                                          ),
                                          progress: _entrance,
                                          begin: 0.25,
                                          end: 0.65,
                                          child: _Benefit(
                                            asset: 'feature_ai.svg',
                                            title: l10n.premiumBenefitAiTitle,
                                            detail: l10n.premiumBenefitAiDetail,
                                          ),
                                        ),
                                        const SizedBox(height: 24),
                                        PremiumReveal(
                                          key: const ValueKey(
                                            'premium-reveal-voice',
                                          ),
                                          progress: _entrance,
                                          begin: 0.34,
                                          end: 0.74,
                                          child: _Benefit(
                                            asset: 'feature_voice.svg',
                                            title:
                                                l10n.premiumBenefitVoiceTitle,
                                            detail:
                                                l10n.premiumBenefitVoiceDetail,
                                            voiceIcon: true,
                                            emphasizeDetail: true,
                                          ),
                                        ),
                                        const SizedBox(height: 24),
                                        PremiumReveal(
                                          key: const ValueKey(
                                            'premium-reveal-feed',
                                          ),
                                          progress: _entrance,
                                          begin: 0.43,
                                          end: 0.83,
                                          child: _Benefit(
                                            asset: 'feature_feed.svg',
                                            title: l10n.premiumBenefitFeedTitle,
                                            detail:
                                                l10n.premiumBenefitFeedDetail,
                                            emphasizeDetail: true,
                                          ),
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
                          child: PremiumReveal(
                            key: const ValueKey('premium-reveal-cta'),
                            progress: _entrance,
                            begin: .42,
                            end: .9,
                            distance: 8,
                            child: PremiumPressFeedback(
                              enabled: !_showingPlans,
                              child: ElevatedButton(
                                key: const ValueKey('premium-show-plans'),
                                onPressed: _showingPlans ? null : _showPlans,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.white,
                                  foregroundColor: AppColors.accent,
                                  disabledBackgroundColor: AppColors.white,
                                  disabledForegroundColor: AppColors.accent,
                                  minimumSize: const Size(double.infinity, 56),
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
                            ),
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
                child: PremiumPressFeedback(
                  pressedScale: .94,
                  child: Tooltip(
                    message: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    child: AppChromeIconButton(
                      key: const ValueKey('premium-close-benefits'),
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.of(context).pop(),
                      backgroundColor: AppColors.primaryText,
                      iconColor: AppColors.white,
                    ),
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
  const _BenefitsHeader({
    required this.width,
    required this.entrance,
    required this.statistics,
  });

  final double width;
  final Animation<double> entrance;
  final Animation<double> statistics;

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
      progress: statistics,
      label: l10n.premiumRatingLabel,
      leftAsset: 'laurel_left.svg',
      rightAsset: 'laurel_right.svg',
      star: true,
    );
    final passRate = _ProofPoint(
      value: l10n.premiumPassRateValue,
      progress: statistics,
      label: l10n.premiumPassRateLabel,
      leftAsset: 'laurel_pass_left.svg',
      rightAsset: 'laurel_pass_right.svg',
    );
    return Stack(
      children: [
        PremiumReveal(
          key: const ValueKey('premium-reveal-hero'),
          progress: entrance,
          begin: 0,
          end: .6,
          distance: 0,
          child: SizedBox(
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
              PremiumReveal(
                key: const ValueKey('premium-reveal-title'),
                progress: entrance,
                begin: 0,
                end: .52,
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.paywallTitle,
                    textAlign: TextAlign.center,
                    style: headlineStyle.copyWith(fontSize: fontSize),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              PremiumReveal(
                key: const ValueKey('premium-reveal-stats'),
                progress: entrance,
                begin: .1,
                end: .58,
                distance: 10,
                child: largeText
                    ? Column(
                        children: [
                          rating,
                          const SizedBox(height: 16),
                          passRate,
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: rating),
                          const SizedBox(width: 16),
                          Expanded(child: passRate),
                        ],
                      ),
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
    required this.progress,
    required this.label,
    required this.leftAsset,
    required this.rightAsset,
    this.star = false,
  });

  final String value;
  final Animation<double> progress;
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
                          SvgPicture.asset(
                            'assets/images/premium/star.svg',
                            colorFilter: const ColorFilter.mode(
                              AppColors.premiumRatingStar,
                              BlendMode.srcIn,
                            ),
                          ),
                        _CountingProofValue(
                          key: ValueKey(
                            star
                                ? 'premium-rating-value'
                                : 'premium-pass-value',
                          ),
                          value: value,
                          progress: progress,
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
                        color: AppColors.white.withValues(alpha: .6),
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

/// Keeps localized punctuation and the final width throughout the count-up.
/// The enclosing proof point announces only the final statistic to readers.
class _CountingProofValue extends StatelessWidget {
  const _CountingProofValue({
    super.key,
    required this.value,
    required this.progress,
  });

  final String value;
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w700,
      color: AppColors.white,
      height: 1.1,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    final number = RegExp(r'\d+[.,]\d+').firstMatch(value);
    if (number == null) return Text(value, style: style);
    final localizedNumber = number.group(0)!;
    final target = double.parse(localizedNumber.replaceAll(',', '.'));
    final separator = localizedNumber.contains(',') ? ',' : '.';
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final size = painter.size;
    painter.dispose();
    return SizedBox.fromSize(
      size: size,
      child: AnimatedBuilder(
        animation: progress,
        builder: (context, _) {
          final current = (1 + (target - 1) * progress.value)
              .toStringAsFixed(1)
              .replaceAll('.', separator);
          return Text(
            value.replaceRange(number.start, number.end, current),
            textAlign: TextAlign.center,
            style: style,
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
    this.inlineDetail = false,
    this.emphasizeDetail = false,
  });

  final String asset;
  final String title;
  final String detail;
  final bool voiceIcon;
  final bool inlineDetail;
  final bool emphasizeDetail;

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(
      fontSize: 19,
      fontWeight: FontWeight.w700,
      height: 1.1,
    );
    final mutedColor = AppColors.white.withValues(alpha: .4);
    final titleStyle = textStyle.copyWith(
      color: emphasizeDetail ? mutedColor : AppColors.white,
    );
    final detailStyle = textStyle.copyWith(
      color: emphasizeDetail ? AppColors.white : mutedColor,
    );
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
                  child: Center(
                    child: SizedBox.square(
                      dimension: 56 * 24 / 80,
                      child: FittedBox(child: icon),
                    ),
                  ),
                )
              : icon,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: inlineDetail
              ? Text.rich(
                  TextSpan(
                    style: textStyle,
                    children: [
                      TextSpan(text: '$title ', style: titleStyle),
                      TextSpan(text: detail, style: detailStyle),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: titleStyle),
                    Text(detail, style: detailStyle),
                  ],
                ),
        ),
      ],
    );
  }
}
