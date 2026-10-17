import 'dart:async';
import 'package:pdd_app/core/config/game_economy.dart';
import 'package:intl/intl.dart';
import 'package:pdd_app/presentation/widgets/user_avatar.dart';
import 'package:pdd_app/presentation/widgets/app_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/data/services/auth_service.dart';
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
  /// Показанный рейтинг: сначала сохранённый (сразу), затем свежий с сервера.
  /// Без связи сервис возвращает последний удачный ответ с пометкой stale.
  GameLeaderboard? _board;
  bool _loading = true;
  Timer? _timer;

  Future<void> _refresh() async {
    if (mounted) setState(() => _loading = true);
    if (_board == null) {
      final saved = await GameLeaderboardService.instance.lastKnown();
      if (mounted && saved != null && _board == null) {
        setState(() => _board = saved);
      }
    }
    final fresh = await GameLeaderboardService.instance.fetch();
    if (!mounted) return;
    setState(() {
      if (fresh != null) _board = fresh;
      _loading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// «13:05» для сегодняшних данных, «16 окт., 13:05» для более старых.
  String _savedAt(DateTime at) {
    final now = DateTime.now();
    final today =
        at.year == now.year && at.month == now.month && at.day == now.day;
    final locale = appL10n.localeName;
    return today
        ? DateFormat.Hm(locale).format(at)
        : DateFormat.MMMd(locale).add_Hm().format(at);
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
              // Обновление поверх уже показанных данных: тонкая полоска, без мигания списка.
              SizedBox(
                height: 2,
                child: _loading && _board != null
                    ? const LinearProgressIndicator(minHeight: 2)
                    : null,
              ),
              const SizedBox(height: 6),
              ..._status(colors),
              Expanded(child: _body(colors)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _status(AppThemeColors colors) {
    final board = _board;
    if (board == null) return const [];
    final small = TextStyle(fontSize: 12, color: colors.secondaryText);
    final end = board.endsAt;
    final me = board.me;
    final savedAt = board.stale ? board.fetchedAt : null;
    return [
      if (end != null)
        Builder(
          builder: (_) {
            final hours = end.difference(DateTime.now()).inHours.clamp(0, 168);
            return Text(
              appL10n.gameRatingResultsIn(hours ~/ 24, hours % 24),
              style: small,
            );
          },
        ),
      if (me?.dailyLimit != null)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            appL10n.gameScoreDailyBudget(me!.dailyEarned ?? 0, me.dailyLimit!),
            style: small,
          ),
        ),
      if (savedAt != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Material(
            color: colors.background,
            borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
              onTap: _loading ? null : _refresh,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.wifi_off_rounded,
                      size: 16,
                      color: colors.secondaryText,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        appL10n.gameRatingStaleAt(_savedAt(savedAt)),
                        style: small,
                      ),
                    ),
                    Text(
                      appL10n.gameRatingReload,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _loading ? colors.secondaryText : colors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      const SizedBox(height: 12),
    ];
  }

  Widget _body(AppThemeColors colors) {
    final board = _board;
    if (board == null) {
      if (_loading) return const Center(child: AppLoadingIndicator());
      return _Message(
        icon: Icons.wifi_off_rounded,
        text: appL10n.gameRatingUnavailable,
        onRetry: _refresh,
      );
    }
    final me = board.me;
    final signedIn = AuthService.instance.currentUser != null;
    // Своя строка снизу: вне топа — с местом, без очков за неделю — с нулём,
    // без входа — подсказка. Прочерков вместо чисел не показываем.
    final Widget? pinned = me != null
        ? (me.rank > board.top.length ? GameLeaderboardRow(entry: me) : null)
        : signedIn
        ? GameLeaderboardRow(
            entry: GameLeaderboardEntry(
              rank: 0,
              name: AuthService.instance.currentUser!.name,
              score: 0,
              runs: 0,
              isMe: true,
              avatarUrl: AuthService.instance.currentUser!.avatarUrl,
            ),
            note: appL10n.gameRatingNotRanked,
          )
        : _Hint(text: appL10n.gameRatingSignIn);
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: board.top.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 40),
                      _Message(
                        icon: Icons.flag_rounded,
                        text: appL10n.gameRatingEmpty,
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: board.top.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, i) =>
                        GameLeaderboardRow(entry: board.top[i]),
                  ),
          ),
        ),
        if (pinned != null) ...[const SizedBox(height: 8), pinned],
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint({required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
      ),
      child: Row(
        children: [
          Icon(Icons.login_rounded, size: 20, color: colors.secondaryText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: colors.secondaryText),
            ),
          ),
        ],
      ),
    );
  }
}

class GameLeaderboardRow extends StatelessWidget {
  final GameLeaderboardEntry entry;

  /// Подпись вместо «Вы»/«N заездов» (например, «Сыграйте, чтобы попасть…»).
  final String? note;
  const GameLeaderboardRow({super.key, required this.entry, this.note});

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
              entry.rank > 0 ? '${entry.rank}' : '',
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
                  note ??
                      (entry.isMe
                          ? appL10n.gameRatingYou
                          : appL10n.gameRatingRuns(entry.runs)),
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
            TextButton(
              onPressed: onRetry,
              child: Text(appL10n.gameRatingReload),
            ),
        ],
      ),
    );
  }
}
