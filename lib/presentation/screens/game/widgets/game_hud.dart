import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/data/services/game_garage_service.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_garage.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/presentation/screens/game/controllers/game_controller.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_fuel_widgets.dart';

class GameHud extends StatelessWidget {
  final GameState state;
  final VoidCallback? onGarage;

  /// Hidden until the player has earned a second car: with one car there is
  /// nothing to choose.
  final bool showGarage;
  final VoidCallback? onGarageLongPress;
  final VoidCallback? onLeaderboard;
  final String vehicleId;
  final String vehiclePaint;
  final GameThumbnailLoader? thumbnail;
  final Map<String, Uint8List> thumbnailCache;
  const GameHud({
    super.key,
    required this.state,
    this.onGarage,
    this.showGarage = true,
    this.onGarageLongPress,
    this.onLeaderboard,
    this.vehicleId = 'hatch',
    this.vehiclePaint = 'red',
    this.thumbnail,
    this.thumbnailCache = const {},
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final notice =
        state.lastViolation != null &&
            state.lastViolation != 'oncoming' &&
            state.lastViolation != 'one_way'
        ? state.lastViolation
        : state.oncoming
        ? (state.lane == 'against' ? 'one_way' : 'oncoming')
        : null;
    // A coloured pill with a white icon and value (design: HUD counters).
    Widget metric(String icon, Color color, String value) => Container(
      key: ValueKey('hud-$icon'),
      padding: const EdgeInsets.fromLTRB(7, 6, 8, 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(90),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: Center(
              child: SvgPicture.asset(
                'assets/icons/game/$icon.svg',
                colorFilter: const ColorFilter.mode(
                  AppColors.white,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Onest',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.white,
              height: 1,
            ),
          ),
        ],
      ),
    );
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Long-press on the gauge opens the weather/season sheet
                    // (the garage button may be hidden).
                    GestureDetector(
                      onLongPress: onGarageLongPress,
                      child: GameFuelGauge(
                        fuel: state.fuel,
                        maxFuel: GameState.maxFuel,
                        unlimited: state.fuelUnlimited,
                      ),
                    ),
                    if (showGarage) const SizedBox(height: 20),
                    // The button shows the car being driven: choosing a
                    // different model in the garage changes it here too. It is
                    // greyed while controls are locked so the HUD never jumps;
                    // Tooltip is avoided because it swallows the long-press.
                    if (showGarage)
                      Opacity(
                        opacity: onGarage != null ? 1 : 0.55,
                        child: Material(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(8),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: onGarage,
                            onLongPress: onGarageLongPress,
                            child: Semantics(
                              button: true,
                              enabled: onGarage != null,
                              label: appL10n.gameGarage,
                              child: SizedBox(
                                width: 68,
                                height: 52,
                                // The car fills the card (the render has
                                // transparent margins round the model).
                                child: Center(
                                  child: Transform.scale(
                                    scale: 1.45,
                                    child: SizedBox(
                                      width: 49,
                                      height: 38,
                                      child: ExcludeSemantics(
                                        child: GameCarThumbnail(
                                          car: GameCar(vehicleId, vehiclePaint),
                                          loader: thumbnail,
                                          cache: thumbnailCache,
                                        ),
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
                const SizedBox(width: 16),
                Expanded(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 4,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (state.limitKmH != null)
                          // A miniature 3.24 sign: the limit currently in force.
                          Semantics(
                            label: appL10n.gameSpeedLimitLabel(state.limitKmH!),
                            child: Container(
                              width: 36,
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppColors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: colors.red, width: 4),
                              ),
                              child: Text(
                                '${state.limitKmH}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1A1A1A),
                                  height: 1,
                                ),
                              ),
                            ),
                          ),
                        Semantics(
                          label:
                              '${appL10n.gameViolations}: ${state.violationCount}',
                          child: metric(
                            'hud_warning',
                            colors.red,
                            '${state.violationCount}',
                          ),
                        ),
                        metric(
                          'hud_location',
                          AppColors.primaryText,
                          state.distanceM >= 1000
                              ? '${(state.distanceM / 1000).toStringAsFixed(1)} ${appL10n.gameKilometers}'
                              : '${state.distanceM} ${appL10n.gameMeters}',
                        ),
                        // Tapping the score opens the weekly rating.
                        GestureDetector(
                          onTap: onLeaderboard,
                          child: Semantics(
                            button: onLeaderboard != null,
                            label: appL10n.gameWeeklyRating,
                            child: metric(
                              'hud_star',
                              colors.gold,
                              '${state.score}',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: notice == null
                  ? const SizedBox.shrink()
                  : Padding(
                      key: ValueKey(notice),
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: colors.red,
                          borderRadius: BorderRadius.circular(
                            AppDimensions.smallRadius,
                          ),
                        ),
                        child: Text(
                          switch (notice) {
                            'oncoming' => appL10n.gameOncoming,
                            'one_way' => appL10n.gameOneWayAgainst,
                            'roadworks' => appL10n.gameRoadworksHit,
                            'collision' => appL10n.gameCollision,
                            'offroad' => appL10n.gameOffroad,
                            'priority' => appL10n.gamePriorityViolation,
                            'speeding' => appL10n.gameSpeeding,
                            'overtaking' => appL10n.gameOvertakingProhibited,
                            'pedestrian' => appL10n.gamePedestrianYield,
                            _ => appL10n.gameWrongManeuver,
                          },
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
