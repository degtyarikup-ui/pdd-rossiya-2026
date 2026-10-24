import 'package:pdd_app/data/models/streak.dart';
import 'package:pdd_app/presentation/widgets/streak_celebration_dialog.dart';
import 'package:pdd_app/presentation/widgets/celebration_screen.dart';

import 'package:flutter/material.dart';
import 'package:pdd_app/data/models/achievement.dart';
import 'package:pdd_app/data/services/achievement_award_service.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/profile/widgets/achievement_badge.dart';
import 'package:pdd_app/presentation/widgets/achievement_labels.dart';
import 'package:pdd_app/presentation/widgets/app_loading_indicator.dart';

/// Older/native-less game summaries still use Flutter's result dialog.
Future<void> showCompletionAchievementAwards(
  BuildContext context,
  AchievementAwardService service,
) async {
  final streak = await service.pendingStreak();
  final pending = await service.pending();
  final total = pending.length + (streak == null ? 0 : 1);
  for (var index = 0; index < total; index++) {
    if (!context.mounted) return;
    final isStreak = streak != null && index == 0;
    final awardIndex = index - (streak == null ? 0 : 1);
    var closing = false;
    final next = await showGeneralDialog<bool>(
      context: context,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, _, _) {
        void close(bool next) {
          if (closing) return;
          closing = true;
          Navigator.of(context).pop(next);
        }

        return isStreak
            ? StreakCelebrationView(
                streak: streak,
                position: index + 1,
                total: total,
                onContinue: () => close(true),
                onClose: () => close(false),
              )
            : AchievementAwardScreen(
                achievement: pending[awardIndex],
                position: index + 1,
                total: total,
                onContinue: () => close(true),
                onClose: () => close(false),
              );
      },
    );
    try {
      if (isStreak) {
        await service.acknowledgeStreak(streak);
      } else {
        final award = pending[awardIndex];
        await service.acknowledge(award.id, award.level);
      }
    } catch (_) {}
    if (next != true) return;
  }
}

/// Mounted only at a completed activity's boundary. The result (and its review
/// prompt) is built after awards, so nothing can cover the congratulations.
class CompletionAchievementAwards extends StatefulWidget {
  const CompletionAchievementAwards({
    super.key,
    required this.service,
    required this.resultBuilder,
  });

  final AchievementAwardService service;
  final WidgetBuilder resultBuilder;

  @override
  State<CompletionAchievementAwards> createState() =>
      _CompletionAchievementAwardsState();
}

class _CompletionAchievementAwardsState
    extends State<CompletionAchievementAwards> {
  List<AchievementProgress>? _pending;
  Streak? _streak;
  bool _showStreak = false;
  int _index = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final streak = await widget.service.pendingStreak();
    final pending = await widget.service.pending();
    if (mounted) {
      setState(() {
        _streak = streak;
        _showStreak = streak != null;
        _pending = pending;
      });
    }
  }

  Future<void> _advance({bool close = false}) async {
    if (_saving) return;
    _saving = true;
    try {
      if (_showStreak) {
        await widget.service.acknowledgeStreak(_streak!);
      } else {
        final award = _pending![_index];
        await widget.service.acknowledge(award.id, award.level);
      }
    } catch (_) {
      // The result is still accessible when the device cannot save a receipt.
    }
    if (!mounted) return;
    setState(() {
      if (close) {
        _showStreak = false;
        _index = _pending!.length;
      } else if (_showStreak) {
        _showStreak = false;
      } else {
        _index++;
      }
      _saving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    if (pending == null) {
      return const Scaffold(body: Center(child: AppLoadingIndicator()));
    }
    if (!_showStreak && _index >= pending.length) {
      return widget.resultBuilder(context);
    }
    final total = pending.length + (_streak == null ? 0 : 1);
    final screen = _showStreak
        ? StreakCelebrationView(
            key: const ValueKey('activity-streak'),
            streak: _streak!,
            onContinue: () => _advance(),
            onClose: () => _advance(close: true),
            position: 1,
            total: total,
          )
        : AchievementAwardScreen(
            key: ValueKey(
              '${pending[_index].id.name}/${pending[_index].level}',
            ),
            achievement: pending[_index],
            onContinue: () => _advance(),
            onClose: () => _advance(close: true),
            position: _index + 1 + (_streak == null ? 0 : 1),
            total: total,
          );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _advance(close: true);
      },
      child: AnimatedSwitcher(
        duration: Duration(
          milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 240,
        ),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: screen,
      ),
    );
  }
}

class AchievementAwardScreen extends StatelessWidget {
  const AchievementAwardScreen({
    super.key,
    required this.achievement,
    required this.onContinue,
    required this.onClose,
    this.position = 1,
    this.total = 1,
  });
  final AchievementProgress achievement;
  final VoidCallback onContinue, onClose;
  final int position, total;
  @override
  Widget build(BuildContext context) => CelebrationScreen(
    heading: appL10n.achievementAwardTitle,
    title: achievementTitle(achievement.id),
    description: achievementDescription(achievement.id),
    label: appL10n.achievementLevelFormat(
      achievement.level,
      achievement.levels.length,
    ),
    heroBuilder: (size) => AchievementBadge(
      id: achievement.id,
      imageLevel: achievement.level,
      unlocked: true,
      size: size,
      highQuality: true,
    ),
    onContinue: onContinue,
    onClose: onClose,
    position: position,
    total: total,
  );
}
