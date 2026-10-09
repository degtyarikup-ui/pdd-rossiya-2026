import 'package:pdd_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/game_situation.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_ticket_badge.dart';

class GameExplanationSheet extends StatelessWidget {
  final GameSituation situation;
  final VoidCallback onContinue;
  final VoidCallback? onShowSourceImage;
  final bool sourceOpen;

  /// No answer was chosen before the countdown ran out.
  final bool timedOut;

  const GameExplanationSheet({
    super.key,
    required this.situation,
    required this.onContinue,
    this.onShowSourceImage,
    this.sourceOpen = false,
    this.timedOut = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(sourceOpen ? 0 : AppDimensions.cardRadius),
        ),
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.50,
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Keep the source ticket and answer status on one line.
                Row(
                  children: [
                    Flexible(
                      child: GameTicketBadge(
                        ticket: situation.ticket,
                        onTap: onShowSourceImage,
                        open: sourceOpen,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colors.redLight,
                        borderRadius: BorderRadius.circular(
                          AppDimensions.radiusSmall,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: colors.red,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            timedOut ? appL10n.gameTimeUp : appL10n.gameMistake,
                            style: TextStyle(
                              fontFamily: 'Onest',
                              fontSize: 12,
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

                // The right answer first: the question card is gone by now,
                // so this is the only place the player can see it.
                if (situation.correctAnswerIndex >= 0 &&
                    situation.correctAnswerIndex < situation.options.length)
                  Container(
                    key: const ValueKey('game-correct-answer'),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: colors.greenLight,
                      borderRadius: BorderRadius.circular(
                        AppDimensions.smallRadius,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 20,
                          color: colors.green,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '${appL10n.gameCorrectAnswer}: ',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                TextSpan(
                                  text: situation
                                      .options[situation.correctAnswerIndex],
                                ),
                              ],
                            ),
                            style: TextStyle(
                              fontFamily: 'Onest',
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: colors.primaryText,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Explanation Text
                Text(
                  situation.explanation,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colors.primaryText,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),

                // Continue Button
                ElevatedButton(
                  onPressed: () {
                    HapticFeedbackHelper.tap();
                    onContinue();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppDimensions.radiusMedium,
                      ),
                    ),
                  ),
                  child: Text(
                    appL10n.gameContinue,
                    style: TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
