import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_garage.dart';

/// The game's start screen, laid over the engine's garage scene. No cards:
/// the car stands in the middle and is browsed by swiping or the side
/// arrows; top — fuel and the record; right — round colour and rating
/// buttons; bottom — «Start the drive» (or [blocker] when driving is not
/// possible: sign-in card, empty tank).
class GameLobby extends StatelessWidget {
  final String vehiclePaint;
  final int bestScore;
  final Widget fuel;
  final Widget? blocker;
  final VoidCallback? onStart;

  /// Null when there is only one car to choose from.
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// Null when the car has a single colour.
  final VoidCallback? onColour;
  final VoidCallback? onLeaderboard;

  const GameLobby({
    super.key,
    required this.vehiclePaint,
    required this.bestScore,
    required this.fuel,
    this.blocker,
    this.onStart,
    this.onPrevious,
    this.onNext,
    this.onColour,
    this.onLeaderboard,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final paint = gamePaintColors[vehiclePaint] ?? colors.accent;
    // Light paints (white, silver, yellow…) get a dark icon for contrast.
    final onPaint = paint.computeLuminance() > 0.55
        ? AppColors.primaryText
        : AppColors.white;
    Widget round({
      required Color color,
      required Widget icon,
      required String label,
      VoidCallback? onTap,
      double size = 56,
    }) => Semantics(
      button: true,
      label: label,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(child: icon),
          ),
        ),
      ),
    );
    Widget arrow(IconData icon, String label, VoidCallback onTap) => round(
      color: AppColors.white.withValues(alpha: 0.88),
      size: 46,
      label: label,
      onTap: () {
        HapticFeedbackHelper.select();
        onTap();
      },
      icon: Icon(icon, color: colors.accent, size: 28),
    );
    return Stack(
      children: [
        // Swiping anywhere on the scene browses the cars.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (details) {
              final v = details.primaryVelocity ?? 0;
              if (v < -250 && onNext != null) {
                HapticFeedbackHelper.select();
                onNext!();
              } else if (v > 250 && onPrevious != null) {
                HapticFeedbackHelper.select();
                onPrevious!();
              }
            },
          ),
        ),
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
        // Arrows either side of the car.
        if (onPrevious != null)
          Align(
            alignment: const Alignment(-0.92, -0.05),
            child: arrow(
              Icons.chevron_left_rounded,
              MaterialLocalizations.of(context).previousPageTooltip,
              onPrevious!,
            ),
          ),
        if (onNext != null)
          Align(
            alignment: const Alignment(0.92, -0.05),
            child: arrow(
              Icons.chevron_right_rounded,
              MaterialLocalizations.of(context).nextPageTooltip,
              onNext!,
            ),
          ),
        // Bottom: the start button (or the blocker), round buttons above it
        // on the right: the car's colour and the weekly rating.
        Positioned(
          left: 16,
          right: 16,
          bottom: 16 + bottomInset,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (onColour != null)
                round(
                  color: paint,
                  label: gamePaintName(vehiclePaint),
                  onTap: onColour,
                  icon: Icon(Icons.palette_rounded, color: onPaint, size: 26),
                ),
              if (onColour != null) const SizedBox(height: 12),
              round(
                color: colors.gold,
                label: appL10n.gameWeeklyRating,
                onTap: onLeaderboard,
                icon: const Icon(
                  Icons.leaderboard_rounded,
                  color: AppColors.white,
                  size: 26,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child:
                    blocker ??
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
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A compact sheet of the car's available colours.
Future<String?> showGamePaintSheet(
  BuildContext context, {
  required List<String> paints,
  required String selected,
}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final colors = AppColors.of(context);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final paint in paints)
                Semantics(
                  button: true,
                  selected: paint == selected,
                  label: gamePaintName(paint),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedbackHelper.select();
                      Navigator.pop(context, paint);
                    },
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: gamePaintColors[paint],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: paint == selected
                              ? colors.accent
                              : colors.divider,
                          width: paint == selected ? 3 : 1,
                        ),
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
