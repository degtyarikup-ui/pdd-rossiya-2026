import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/data/services/game_garage_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_garage.dart';

/// Full-screen chrome over the engine's garage scene: the title at the top,
/// a hint while the doors are closed, and "choose"/"close" once the car has
/// rolled out. The middle stays transparent so touches reach the WebView
/// (tap opens the doors, a drag spins the car).
class GameRevealOverlay extends StatelessWidget {
  final GameCar car;
  final bool shown;
  final VoidCallback onChoose;
  final VoidCallback onClose;

  const GameRevealOverlay({
    super.key,
    required this.car,
    required this.shown,
    required this.onChoose,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final padding = MediaQuery.paddingOf(context);
    final isCyber = car.id == GameGarageService.cyber;
    return Stack(
      children: [
        Positioned(
          top: padding.top + 24,
          left: 20,
          right: 20,
          child: IgnorePointer(
            child: Column(
              children: [
                Text(
                  appL10n.gameRevealTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: isCyber ? colors.gold : Colors.white,
                    shadows: const [
                      Shadow(color: Color(0x99000000), blurRadius: 12),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${gameCarName(car.id)} · ${gamePaintName(car.paint)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Color(0xE6FFFFFF),
                    shadows: [Shadow(color: Color(0x99000000), blurRadius: 10)],
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: padding.bottom + 20,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: shown
                ? Column(
                    key: const ValueKey('buttons'),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton(
                        onPressed: onChoose,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isCyber
                              ? colors.gold
                              : colors.accent,
                          foregroundColor: isCyber
                              ? const Color(0xFF2A1F08)
                              : Colors.white,
                          elevation: 0,
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppDimensions.radiusMedium,
                            ),
                          ),
                        ),
                        child: Text(
                          appL10n.gameRevealChoose,
                          style: const TextStyle(
                            fontFamily: 'Onest',
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: onClose,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(44),
                        ),
                        child: Text(
                          appL10n.gameRevealClose,
                          style: const TextStyle(
                            fontFamily: 'Onest',
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  )
                : IgnorePointer(
                    key: const ValueKey('hint'),
                    child: Text(
                      appL10n.gameRevealTap,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xE6FFFFFF),
                        shadows: [
                          Shadow(color: Color(0x99000000), blurRadius: 10),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
