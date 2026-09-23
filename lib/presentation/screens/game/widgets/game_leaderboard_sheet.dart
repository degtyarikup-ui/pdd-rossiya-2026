import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/data/services/game_leaderboard_service.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Weekly top-100 by points; the player's own row is highlighted and, if
/// outside the top, pinned at the bottom.
class GameLeaderboardSheet extends StatefulWidget {
  const GameLeaderboardSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const GameLeaderboardSheet(),
    );
  }

  @override
  State<GameLeaderboardSheet> createState() => _GameLeaderboardSheetState();
}

class _GameLeaderboardSheetState extends State<GameLeaderboardSheet> {
  late Future<GameLeaderboard?> _future = GameLeaderboardService.instance
      .fetch();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.78;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.emoji_events_rounded,
                    color: colors.gold,
                    size: 26,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      appL10n.gameWeeklyRating,
                      style: TextStyle(
                        fontFamily: 'Onest',
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<GameLeaderboard?>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final board = snapshot.data;
                    if (board == null) {
                      return _Message(
                        icon: Icons.wifi_off_rounded,
                        text: appL10n.gameRatingUnavailable,
                        onRetry: () => setState(
                          () =>
                              _future = GameLeaderboardService.instance.fetch(),
                        ),
                      );
                    }
                    if (board.top.isEmpty) {
                      return _Message(
                        icon: Icons.flag_rounded,
                        text: appL10n.gameRatingEmpty,
                      );
                    }
                    final me = board.me;
                    final pinMe = me != null && me.rank > board.top.length;
                    final days = board.endsAt == null
                        ? null
                        : board.endsAt!.difference(DateTime.now()).inDays + 1;
                    return Column(
                      children: [
                        if (days != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              appL10n.gameRatingEndsIn(days.clamp(1, 7)),
                              style: TextStyle(
                                fontFamily: 'Onest',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.secondaryText,
                              ),
                            ),
                          ),
                        Expanded(
                          child: ListView.separated(
                            itemCount: board.top.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, i) =>
                                _Row(entry: board.top[i]),
                          ),
                        ),
                        if (pinMe) ...[
                          const SizedBox(height: 8),
                          _Row(entry: me),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final GameLeaderboardEntry entry;
  const _Row({required this.entry});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final medal = switch (entry.rank) {
      1 => colors.gold,
      2 => const Color(0xFFA7B1BC),
      3 => const Color(0xFFC98A5A),
      _ => null,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: entry.isMe ? colors.accentSurface10 : colors.searchFieldFill,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: medal != null
                ? Icon(Icons.emoji_events_rounded, color: medal, size: 22)
                : Text(
                    '${entry.rank}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: colors.secondaryText,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.isMe
                      ? '${entry.name} · ${appL10n.gameRatingYou}'
                      : entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 14,
                    fontWeight: entry.isMe ? FontWeight.w800 : FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
                Text(
                  appL10n.gameRatingRuns(entry.runs),
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 11,
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.star_rounded, size: 18, color: colors.gold),
          const SizedBox(width: 3),
          Text(
            '${entry.score}',
            style: TextStyle(
              fontFamily: 'Onest',
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: colors.gold,
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onRetry;
  const _Message({required this.icon, required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: colors.secondaryText),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Onest', color: colors.secondaryText),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: Text(appL10n.gameRestart)),
        ],
      ),
    );
  }
}
