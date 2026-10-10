import 'dart:async';
import 'package:pdd_app/core/config/game_economy.dart';
import 'package:intl/intl.dart';
import 'package:pdd_app/presentation/widgets/user_avatar.dart';
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

  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _showScoreRules() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appL10n.gameScoreRulesTitle),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(appL10n.gameScoreRulesBody),
              const SizedBox(height: 16),
              for (final entry in [
                (
                  appL10n.gameSignSwiperTitle,
                  GameEconomy.signs(1),
                  GameEconomy.signs(99),
                ),
                (
                  appL10n.gameTrafficControllerTitle,
                  GameEconomy.regulator(1),
                  GameEconomy.regulator(99),
                ),
                (
                  appL10n.gameCityTitle,
                  GameEconomy.city(1),
                  GameEconomy.city(99),
                ),
                (
                  appL10n.gameCrossroadsPriorityTitle,
                  GameEconomy.crossroads(1),
                  GameEconomy.crossroads(99),
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    appL10n.gameScoreRewardLine(entry.$1, entry.$2, entry.$3),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                appL10n.gameScoreDailyLimitExplanation(
                  GameEconomy.dailyRatingLimit,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(appL10n.close),
          ),
        ],
      ),
    );
  }

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
                  IconButton(
                    onPressed: _showScoreRules,
                    tooltip: appL10n.gameScoreRulesTitle,
                    icon: const Icon(Icons.info_outline_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              FutureBuilder<GameLeaderboard?>(
                future: _future,
                builder: (context, snapshot) {
                  final end = snapshot.data?.endsAt;
                  if (end == null) return const SizedBox.shrink();
                  final hours = end
                      .difference(DateTime.now())
                      .inHours
                      .clamp(0, 168);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      appL10n.gameRatingResultsIn(hours ~/ 24, hours % 24),
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.secondaryText,
                      ),
                    ),
                  );
                },
              ),
              FutureBuilder<GameLeaderboard?>(
                future: _future,
                builder: (context, snapshot) {
                  final me = snapshot.data?.me;
                  if (me?.dailyLimit == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      appL10n.gameScoreDailyBudget(
                        me!.dailyEarned ?? 0,
                        me.dailyLimit!,
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.secondaryText,
                      ),
                    ),
                  );
                },
              ),
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
                    return Column(
                      children: [
                        Expanded(
                          child: ListView.separated(
                            itemCount: board.top.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, i) =>
                                GameLeaderboardRow(entry: board.top[i]),
                          ),
                        ),
                        if (pinMe) ...[
                          const SizedBox(height: 8),
                          GameLeaderboardRow(entry: me),
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

class GameLeaderboardRow extends StatelessWidget {
  final GameLeaderboardEntry entry;
  const GameLeaderboardRow({super.key, required this.entry});

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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: entry.isMe ? colors.accentSurface10 : colors.background,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.transparent,
            ),
            child: Text(
              '${entry.rank}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: medal ?? colors.primaryText,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 9),
          UserAvatar(url: entry.avatarUrl, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Onest',
                          fontSize: 14,
                          fontWeight: entry.isMe
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: colors.primaryText,
                        ),
                      ),
                    ),
                    if (entry.isPremium) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.verified_rounded,
                        color: colors.gold,
                        size: 15,
                      ),
                    ],
                  ],
                ),
                Text(
                  entry.isMe
                      ? appL10n.gameRatingYou
                      : appL10n.gameRatingRuns(entry.runs),
                  style: TextStyle(fontSize: 11, color: colors.secondaryText),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * .28,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                NumberFormat.decimalPattern('ru').format(entry.score),
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: colors.primaryText,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
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
