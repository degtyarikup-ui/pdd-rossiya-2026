import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_garage.dart';

/// The game's start screen, laid over the engine's garage scene (the car
/// waits in the middle on its lit pad). Top: fuel and the personal record.
/// Bottom card: the car with a «Change» link, the start button — or, when
/// driving is not possible, [blocker] (sign-in card, empty-tank panel) — and
/// the weekly rating.
class GameLobby extends StatelessWidget {
  final String vehicleId;
  final String vehiclePaint;
  final int bestScore;
  final Widget fuel;
  final Widget? blocker;
  final VoidCallback? onStart;
  final VoidCallback? onGarage;
  final VoidCallback? onLeaderboard;

  const GameLobby({
    super.key,
    required this.vehicleId,
    required this.vehiclePaint,
    required this.bestScore,
    required this.fuel,
    this.blocker,
    this.onStart,
    this.onGarage,
    this.onLeaderboard,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Stack(
      children: [
        // Top: fuel on the left, the record in the HUD's gold pill.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(
                children: [
                  fuel,
                  const Spacer(),
                  Semantics(
                    label: '${appL10n.gameLobbyRecord}: $bestScore',
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(9, 7, 11, 7),
                      decoration: BoxDecoration(
                        color: colors.gold,
                        borderRadius: BorderRadius.circular(90),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SvgPicture.asset(
                            'assets/icons/game/hud_star.svg',
                            width: 14,
                            height: 14,
                            colorFilter: const ColorFilter.mode(
                              AppColors.white,
                              BlendMode.srcIn,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${appL10n.gameLobbyRecord} $bestScore',
                            style: const TextStyle(
                              fontFamily: 'Onest',
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.white,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Bottom card.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + bottomInset),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: gamePaintColors[vehiclePaint],
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.divider),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            gameCarName(vehicleId),
                            style: TextStyle(
                              fontFamily: 'Onest',
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: colors.primaryText,
                            ),
                          ),
                          Text(
                            gamePaintName(vehiclePaint),
                            style: TextStyle(
                              fontFamily: 'Onest',
                              fontSize: 13,
                              color: colors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onGarage != null)
                      TextButton.icon(
                        onPressed: onGarage,
                        icon: const Icon(Icons.palette_outlined, size: 18),
                        label: Text(appL10n.gameLobbyChangeCar),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (blocker != null)
                  blocker!
                else
                  SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: onStart,
                      icon: const Icon(Icons.play_arrow_rounded, size: 26),
                      label: Text(
                        appL10n.gameLobbyStart,
                        style: const TextStyle(
                          fontFamily: 'Onest',
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: onLeaderboard,
                  icon: const Icon(Icons.leaderboard_rounded, size: 20),
                  label: Text(appL10n.gameWeeklyRating),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
