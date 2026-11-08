import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/premium_paywall_sheet.dart';
import 'package:pdd_app/presentation/widgets/premium_motion.dart';
import 'package:pdd_app/presentation/widgets/subscription_management_sheet.dart';

/// The profile entry has two states, independent of the daily free allowance.
class PremiumBannerCard extends ConsumerWidget {
  const PremiumBannerCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final isPremium = ref.watch(isPremiumProvider);
    final foreground = isPremium ? AppColors.primaryText : AppColors.white;
    final expiresAt = isPremium
        ? ref.watch(premiumServiceProvider).expiresAt
        : null;
    final subtitleText = expiresAt == null
        ? l10n.premiumBannerSubtitle
        : l10n.premiumBannerValidUntil(
            DateFormat(
              'd MMMM yyyy, HH:mm',
              l10n.localeName,
            ).format(expiresAt.toLocal()),
          );

    void openPremium() {
      if (isPremium) {
        SubscriptionManagementSheet.show(context);
      } else {
        PremiumPaywallSheet.show(context);
      }
    }

    return Semantics(
      button: true,
      value: isPremium ? l10n.premiumBannerActive : null,
      child: PremiumPressFeedback(
        pressedScale: .99,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
          child: Material(
            key: ValueKey(
              isPremium ? 'premium-banner-active' : 'premium-banner-free',
            ),
            color: isPremium ? AppColors.premiumLime : AppColors.accent,
            child: InkWell(
              onTap: openPremium,
              splashColor: foreground.withValues(alpha: 0.12),
              highlightColor: foreground.withValues(alpha: 0.06),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final expandedText =
                      MediaQuery.textScalerOf(context).scale(16) > 21;
                  final titleStyle = TextStyle(
                    fontSize: width >= 480 ? 24 : 19,
                    fontWeight: FontWeight.w700,
                    color: foreground,
                    height: 1.12,
                  );
                  final titlePainter = TextPainter(
                    text: TextSpan(
                      text: l10n.premiumAccessTitle,
                      style: DefaultTextStyle.of(
                        context,
                      ).style.merge(titleStyle),
                    ),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                    locale: Localizations.localeOf(context),
                    maxLines: 1,
                  )..layout();
                  final titleWidth = titlePainter.width.ceilToDouble() + 26;
                  titlePainter.dispose();
                  final title = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: SvgPicture.asset(
                          'assets/images/premium/verified_${isPremium ? 'lime' : 'blue'}.svg',
                          width: 19,
                          height: 19,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(l10n.premiumAccessTitle, style: titleStyle),
                      ),
                    ],
                  );
                  final subtitle = Text(
                    subtitleText,
                    style: TextStyle(
                      fontSize: width >= 480 ? 15 : 13,
                      fontWeight: FontWeight.w400,
                      color: foreground.withValues(alpha: 0.9),
                      height: 1.3,
                    ),
                  );
                  final preferredArtWidth = (width * .42).clamp(100.0, 260.0);
                  // Reserve room for the title before sizing the decoration.
                  // A narrow phone keeps the same side-by-side composition;
                  // only large accessibility text moves the car below it.
                  final artWidth = expandedText
                      ? preferredArtWidth
                      : (width - titleWidth - 28).clamp(
                          100.0,
                          preferredArtWidth,
                        );
                  final artwork = SizedBox(
                    width: artWidth,
                    height: artWidth * .62,
                    child: ExcludeSemantics(
                      child: IgnorePointer(
                        child: PremiumBannerArtwork(isPremium: isPremium),
                      ),
                    ),
                  );

                  // Keep actual layout space for the car, including at large
                  // text scales. Its arrival animation only moves to the right.
                  if (expandedText) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              title,
                              const SizedBox(height: 8),
                              subtitle,
                            ],
                          ),
                        ),
                        Align(alignment: Alignment.centerRight, child: artwork),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 18, 10, 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              title,
                              const SizedBox(height: 8),
                              subtitle,
                            ],
                          ),
                        ),
                      ),
                      artwork,
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared car and rays for Premium surfaces, including the web checkout.
class PremiumBannerArtwork extends StatefulWidget {
  const PremiumBannerArtwork({
    super.key,
    required this.isPremium,
    this.contained = false,
    this.centered = false,
  });

  final bool isPremium;

  /// Checkout headers show the whole car; profile banners let it reach the edge.
  final bool contained;

  /// A centered car with room for rays on the checkout success screen.
  final bool centered;

  @override
  State<PremiumBannerArtwork> createState() => _PremiumBannerArtworkState();
}

class _PremiumBannerArtworkState extends State<PremiumBannerArtwork>
    with SingleTickerProviderStateMixin {
  late final AnimationController _arrival = AnimationController(
    vsync: this,
    duration: PremiumMotion.carArrival,
  );
  late final Animation<double> _driveIn = _arrival.drive(
    CurveTween(curve: Curves.easeOutQuint),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _started = true;
      _arrival.value = 1;
    } else if (!_started && TickerMode.valuesOf(context).enabled) {
      _started = true;
      _arrival.forward();
    }
  }

  @override
  void dispose() {
    _arrival.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final contained = widget.contained || widget.centered;
        final artWidth =
            width *
            (widget.centered
                ? .88
                : contained
                ? 1
                : 1.28);
        final raySize = artWidth * 1.45;
        final car = AnimatedBuilder(
          animation: _driveIn,
          child: RepaintBoundary(
            child: Image.asset(
              'assets/images/premium/car.png',
              fit: BoxFit.contain,
              cacheWidth: 768,
              filterQuality: FilterQuality.medium,
            ),
          ),
          builder: (context, child) => Transform.translate(
            key: const ValueKey('premium-car-arrival'),
            offset: Offset(artWidth * .16 * (1 - _driveIn.value), 0),
            child: Opacity(
              opacity: (_arrival.value / .4).clamp(0, 1),
              child: child,
            ),
          ),
        );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: contained ? 0 : artWidth * -0.21,
              bottom: contained ? 0 : artWidth * -0.60,
              width: contained ? width : raySize,
              height: contained ? constraints.maxHeight : raySize,
              child: contained
                  ? ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (rect) => const RadialGradient(
                        colors: [
                          Colors.white,
                          Colors.white,
                          Colors.transparent,
                        ],
                        stops: [0, .35, 1],
                      ).createShader(rect),
                      child: _RotatingPremiumRays(isPremium: widget.isPremium),
                    )
                  : _RotatingPremiumRays(isPremium: widget.isPremium),
            ),
            if (widget.centered)
              Positioned.fill(
                child: Center(
                  child: SizedBox(width: artWidth, child: car),
                ),
              )
            else
              Positioned(
                right: widget.contained ? 0 : artWidth * -0.28,
                bottom: widget.contained ? 0 : artWidth * -0.11,
                width: artWidth,
                child: car,
              ),
          ],
        );
      },
    );
  }
}

/// Only this decorative layer repaints while the rest of the profile is still.
class _RotatingPremiumRays extends StatefulWidget {
  const _RotatingPremiumRays({required this.isPremium});

  final bool isPremium;

  @override
  State<_RotatingPremiumRays> createState() => _RotatingPremiumRaysState();
}

class _RotatingPremiumRaysState extends State<_RotatingPremiumRays>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 80),
  );
  late final Animation<double> _turns = Tween<double>(
    begin: 105 / 360,
    end: 465 / 360,
  ).animate(_rotation);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _rotation.stop();
    } else if (!_rotation.isAnimating) {
      _rotation.repeat();
    }
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: RotationTransition(
        key: const ValueKey('premium-banner-rays'),
        turns: _turns,
        child: Opacity(
          opacity: 0.78,
          child: Image.asset(
            // Rasterized from the original SVGs to preserve their blur filters.
            'assets/images/premium/rays_${widget.isPremium ? 'lime' : 'blue'}.png',
            fit: BoxFit.contain,
            filterQuality: FilterQuality.low,
          ),
        ),
      ),
    );
  }
}
