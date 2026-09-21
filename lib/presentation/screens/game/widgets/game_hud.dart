import 'dart:typed_data';

import 'package:flutter/material.dart';
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
        state.lastViolation != null && state.lastViolation != 'oncoming'
        ? state.lastViolation
        : state.oncoming
        ? 'oncoming'
        : null;
    Widget surface(Widget child) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
      ),
      child: child,
    );
    Widget metric(IconData icon, Color color, String value) => surface(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
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
                  children: [
                    GameFuelGauge(
                      fuel: state.fuel,
                      maxFuel: GameState.maxFuel,
                      unlimited: state.fuelUnlimited,
                    ),
                    const SizedBox(height: 8),
                    // The button shows the car being driven: choosing a
                    // different model in the garage changes it here too. It is
                    // always present (greyed while controls are locked) so the
                    // HUD never jumps; Tooltip is avoided because it swallows
                    // the long-press used by the debug sheet.
                    Opacity(
                      opacity: onGarage != null ? 1 : 0.55,
                      child: Material(
                        color: colors.cardBackground,
                        borderRadius: BorderRadius.circular(
                          AppDimensions.smallRadius,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: onGarage,
                          onLongPress: onGarageLongPress,
                          child: Semantics(
                            button: true,
                            enabled: onGarage != null,
                            label: appL10n.gameGarage,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: SizedBox(
                                width: 60,
                                height: 42,
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
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
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
                            Icons.warning_amber_rounded,
                            colors.red,
                            '${state.violationCount}',
                          ),
                        ),
                        metric(
                          Icons.route_rounded,
                          colors.accent,
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
                              Icons.star_rounded,
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
