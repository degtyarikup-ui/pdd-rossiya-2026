import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// HUD fuel gauge: a canister with five pips, or the infinity sign for
/// premium players. Replaces the old hearts.
class GameFuelGauge extends StatelessWidget {
  final int fuel;
  final int maxFuel;
  final bool unlimited;

  const GameFuelGauge({
    super.key,
    required this.fuel,
    required this.maxFuel,
    required this.unlimited,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final low = !unlimited && fuel <= 1;
    final tint = low ? colors.red : colors.accent;
    return Semantics(
      label: unlimited
          ? appL10n.gameFuelUnlimited
          : '${appL10n.gameFuel}: $fuel / $maxFuel',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_gas_station_rounded, size: 20, color: tint),
            const SizedBox(width: 6),
            if (unlimited)
              Text(
                '∞',
                style: TextStyle(
                  fontSize: 18,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: tint,
                ),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < maxFuel; i++)
                    Container(
                      width: 7,
                      height: 14,
                      margin: EdgeInsets.only(right: i == maxFuel - 1 ? 0 : 3),
                      decoration: BoxDecoration(
                        color: i < fuel
                            ? tint
                            : colors.gray.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// "Out of fuel": the countdown to the next unit and the premium pitch.
/// On the game screen it is the bottom card; in the results dialog
/// (`compact`) only the pitch is shown, the countdown lives in the header.
class GameFuelEmptyPanel extends StatefulWidget {
  final DateTime? refillAt;
  final VoidCallback onBuyPremium;
  final bool compact;

  const GameFuelEmptyPanel({
    super.key,
    required this.refillAt,
    required this.onBuyPremium,
    this.compact = false,
  });

  @override
  State<GameFuelEmptyPanel> createState() => _GameFuelEmptyPanelState();
}

class _GameFuelEmptyPanelState extends State<GameFuelEmptyPanel> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!widget.compact) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final pitch = GameFuelPremiumPitch(onBuyPremium: widget.onBuyPremium);
    if (widget.compact) return pitch;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GameFuelEmptyIcon(size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appL10n.gameFuelEmptyTitle,
                      style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: colors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      appL10n.gameFuelRefillIn(
                        gameFuelCountdown(widget.refillAt),
                      ),
                      style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          pitch,
        ],
      ),
    );
  }
}

/// "M:SS" until [at]; "0:00" when it has passed or is unknown.
String gameFuelCountdown(DateTime? at) {
  if (at == null) return '0:00';
  final left = at.difference(DateTime.now());
  if (left.isNegative) return '0:00';
  final m = left.inMinutes, s = left.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// The red pump in a tinted circle, used wherever the tank is empty.
class GameFuelEmptyIcon extends StatelessWidget {
  final double size;
  const GameFuelEmptyIcon({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.red.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.local_gas_station_rounded,
        color: colors.red,
        size: size * 0.55,
      ),
    );
  }
}

/// The pitch: a warm gold panel, the infinity sign and one button.
class GameFuelPremiumPitch extends StatelessWidget {
  final VoidCallback onBuyPremium;
  const GameFuelPremiumPitch({super.key, required this.onBuyPremium});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.gold.withValues(alpha: 0.22),
            colors.gold.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '∞',
                style: TextStyle(
                  fontSize: 28,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: colors.gold,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  appL10n.gameFuelPremiumPitch,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 14,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: onBuyPremium,
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.gold,
              foregroundColor: Colors.white,
              elevation: 0,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
              ),
            ),
            child: Text(
              appL10n.gameFuelBuyPremium,
              style: const TextStyle(
                fontFamily: 'Onest',
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
