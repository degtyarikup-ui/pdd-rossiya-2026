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

/// "Out of fuel": countdown to the next unit and the premium pitch. Used
/// both as the bottom card on the game screen and inside the results dialog.
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
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _countdown() {
    final at = widget.refillAt;
    if (at == null) return '0:00';
    final left = at.difference(DateTime.now());
    if (left.isNegative) return '0:00';
    final m = left.inMinutes, s = left.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: EdgeInsets.all(widget.compact ? 14 : 18),
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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.red.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.local_gas_station_rounded, color: colors.red),
              ),
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
                      appL10n.gameFuelRefillIn(_countdown()),
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
          const SizedBox(height: 10),
          Text(
            appL10n.gameFuelEmptyHint,
            style: TextStyle(
              fontFamily: 'Onest',
              fontSize: 13,
              height: 1.35,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: 12),
          // The pitch: a warm gold panel, the infinity sign and one button.
          Container(
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
                          fontSize: 13,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: colors.primaryText,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: widget.onBuyPremium,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.gold,
                    foregroundColor: const Color(0xFF2A1F08),
                    elevation: 0,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppDimensions.radiusMedium,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.workspace_premium_rounded, size: 20),
                  label: Text(
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
          ),
        ],
      ),
    );
  }
}
