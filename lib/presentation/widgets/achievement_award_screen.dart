import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/theme/app_theme.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
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
  final pending = await service.pending();
  for (var index = 0; index < pending.length; index++) {
    if (!context.mounted) return;
    final award = pending[index];
    final next = await showGeneralDialog<bool>(
      context: context,
      transitionDuration: Duration.zero,
      pageBuilder: (context, _, _) => AchievementAwardScreen(
        achievement: award,
        position: index + 1,
        total: pending.length,
        onContinue: () => Navigator.of(context).pop(true),
        onClose: () => Navigator.of(context).pop(false),
      ),
    );
    try {
      await service.acknowledge(award.id, award.level);
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
  int _index = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pending = await widget.service.pending();
    if (mounted) setState(() => _pending = pending);
  }

  Future<void> _advance({bool close = false}) async {
    if (_saving) return;
    _saving = true;
    final award = _pending![_index];
    try {
      await widget.service.acknowledge(award.id, award.level);
    } catch (_) {
      // The result is still accessible when the device cannot save a receipt.
    }
    if (!mounted) return;
    setState(() {
      _index = close ? _pending!.length : _index + 1;
      _saving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    if (pending == null) {
      return const Scaffold(body: Center(child: AppLoadingIndicator()));
    }
    if (_index >= pending.length) return widget.resultBuilder(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _advance(close: true);
      },
      child: AchievementAwardScreen(
        key: ValueKey('${pending[_index].id.name}/${pending[_index].level}'),
        achievement: pending[_index],
        onContinue: () => _advance(),
        onClose: () => _advance(close: true),
        position: _index + 1,
        total: pending.length,
      ),
    );
  }
}

class AchievementAwardScreen extends StatefulWidget {
  const AchievementAwardScreen({
    super.key,
    required this.achievement,
    required this.onContinue,
    required this.onClose,
    this.position = 1,
    this.total = 1,
  });

  final AchievementProgress achievement;
  final VoidCallback onContinue;
  final VoidCallback onClose;
  final int position;
  final int total;

  @override
  State<AchievementAwardScreen> createState() => _AchievementAwardScreenState();
}

class _AchievementAwardScreenState extends State<AchievementAwardScreen> {
  final _backdropKey = GlobalKey();
  final _badgeKey = GlobalKey();
  final _scrollController = ScrollController();
  Offset? _glowCenter;
  double _glowBadgeSize = 160;
  bool _positionScheduled = false;

  @override
  void initState() {
    super.initState();
    HapticFeedbackHelper.success();
    _scrollController.addListener(_syncGlowPosition);
  }

  void _syncGlowPosition() {
    if (_positionScheduled) return;
    _positionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _positionScheduled = false;
      if (!mounted) return;
      final badge = _badgeKey.currentContext?.findRenderObject();
      final backdrop = _backdropKey.currentContext?.findRenderObject();
      if (badge is! RenderBox || backdrop is! RenderBox) return;
      final center = badge.localToGlobal(
        badge.size.center(Offset.zero),
        ancestor: backdrop,
      );
      if (_glowCenter == center && _glowBadgeSize == badge.size.width) return;
      setState(() {
        _glowCenter = center;
        _glowBadgeSize = badge.size.width;
      });
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final award = widget.achievement;
    final reduced = MediaQuery.disableAnimationsOf(context);
    _syncGlowPosition();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.accent,
      ),
      child: Scaffold(
        backgroundColor: AppColors.accent,
        body: Stack(
          key: _backdropKey,
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: CustomPaint(
                painter: _AwardGlow(
                  center: _glowCenter,
                  badgeSize: _glowBadgeSize,
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.all(AppDimensions.screenPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const SizedBox(width: 48),
                            Expanded(
                              child: Text(
                                appL10n.achievementAwardTitle,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.white,
                                ),
                              ),
                            ),
                            IconButton.filled(
                              tooltip: appL10n.close,
                              style: IconButton.styleFrom(
                                backgroundColor: AppColors.white,
                                foregroundColor: AppColors.primaryText,
                                minimumSize: const Size(48, 48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppDimensions.buttonRadius,
                                  ),
                                ),
                              ),
                              onPressed: widget.onClose,
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final badgeSize = math.min(
                                160.0,
                                math.max(128.0, constraints.maxHeight * .28),
                              );
                              return SingleChildScrollView(
                                controller: _scrollController,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: constraints.maxHeight,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      TweenAnimationBuilder<double>(
                                        tween: Tween(
                                          begin: reduced ? 1 : .82,
                                          end: 1,
                                        ),
                                        duration: Duration(
                                          milliseconds: reduced ? 0 : 650,
                                        ),
                                        curve: Curves.easeOutBack,
                                        builder: (context, scale, child) =>
                                            Transform.scale(
                                              scale: scale,
                                              child: child,
                                            ),
                                        child: AchievementBadge(
                                          key: _badgeKey,
                                          id: award.id,
                                          imageLevel: award.level,
                                          unlocked: true,
                                          size: badgeSize,
                                          highQuality: true,
                                        ),
                                      ),
                                      const SizedBox(height: 32),
                                      Semantics(
                                        liveRegion: true,
                                        child: Text(
                                          achievementTitle(award.id),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 30,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.white,
                                            height: 1.15,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        achievementDescription(award.id),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 16,
                                          height: 1.45,
                                          color: AppColors.white.withValues(
                                            alpha: .8,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 7,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.white.withValues(
                                            alpha: .16,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            40,
                                          ),
                                        ),
                                        child: Text(
                                          appL10n.achievementLevelFormat(
                                            award.level,
                                            award.levels.length,
                                          ),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.white,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        if (widget.total > 1) ...[
                          Text(
                            appL10n.achievementAwardPosition(
                              widget.position,
                              widget.total,
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.white,
                            foregroundColor: AppColors.accent,
                            minimumSize: const Size.fromHeight(56),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                AppDimensions.buttonRadius,
                              ),
                            ),
                            textStyle: const TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: widget.onContinue,
                          child: Text(appL10n.continueButton),
                        ),
                      ],
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

class _AwardGlow extends CustomPainter {
  const _AwardGlow({required this.center, required this.badgeSize});

  final Offset? center;
  final double badgeSize;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = center ?? Offset(size.width / 2, size.height * .4);
    final rayRadius = badgeSize * 2.45;
    final rayPaint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
      ..shader = RadialGradient(
        colors: [
          AppColors.white.withValues(alpha: 0),
          AppColors.white.withValues(alpha: .18),
          AppColors.white.withValues(alpha: .12),
          AppColors.white.withValues(alpha: .035),
          AppColors.white.withValues(alpha: 0),
        ],
        stops: const [0, .18, .4, .72, 1],
      ).createShader(Rect.fromCircle(center: origin, radius: rayRadius));
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6 - math.pi / 2;
      final path = Path()
        ..moveTo(origin.dx, origin.dy)
        ..lineTo(
          origin.dx + math.cos(a - .095) * rayRadius,
          origin.dy + math.sin(a - .095) * rayRadius,
        )
        ..lineTo(
          origin.dx + math.cos(a + .095) * rayRadius,
          origin.dy + math.sin(a + .095) * rayRadius,
        )
        ..close();
      canvas.drawPath(path, rayPaint);
    }
    final glowRadius = badgeSize * 1.55;
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(1, 1 / 1.4);
    canvas.drawCircle(
      Offset.zero,
      glowRadius,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                AppColors.white.withValues(alpha: .92),
                AppColors.white.withValues(alpha: .84),
                AppColors.white.withValues(alpha: .46),
                AppColors.white.withValues(alpha: .1),
                AppColors.white.withValues(alpha: 0),
              ],
              stops: const [0, .18, .42, .7, 1],
            ).createShader(
              Rect.fromCircle(center: Offset.zero, radius: glowRadius),
            ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AwardGlow oldDelegate) =>
      center != oldDelegate.center || badgeSize != oldDelegate.badgeSize;
}
