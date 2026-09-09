import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/feed_item.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/premium_service.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/presentation/widgets/premium_paywall_sheet.dart';
import 'package:pdd_app/presentation/widgets/question_image.dart';

class FeedCard extends ConsumerStatefulWidget {
  final FeedItem item;
  final bool isCurrent;
  final bool isSoundEnabled;
  final int? initialSelectedAnswerIndex;
  final ValueChanged<int>? onAnswerRecorded;
  final VoidCallback onToggleSound;
  final VoidCallback onAutoNext;
  final VoidCallback onPrevious;
  final void Function(double progress, int remainingSeconds)? onTimerTick;
  final void Function(bool isAnswered, bool isCorrect)? onAnswerStateChanged;
  final bool isPaused;
  final ValueChanged<bool>? onFavoriteChanged;

  const FeedCard({
    super.key,
    required this.item,
    required this.isCurrent,
    required this.isSoundEnabled,
    this.isPaused = false,
    this.initialSelectedAnswerIndex,
    this.onAnswerRecorded,
    required this.onToggleSound,
    required this.onAutoNext,
    required this.onPrevious,
    this.onTimerTick,
    this.onAnswerStateChanged,
    this.onFavoriteChanged,
  });

  @override
  ConsumerState<FeedCard> createState() => _FeedCardState();
}

class _FeedCardState extends ConsumerState<FeedCard>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late AnimationController _timerController;
  final ScrollController _scrollController = ScrollController();
  int? _selectedAnswerIndex;
  bool _isAnswered = false;
  Timer? _autoAdvanceTimer;
  int? _lastTickedSecond;

  Duration get _calculatedDuration {
    final textLen = widget.item.questionText.length +
        widget.item.answers.join('').length;
    final baseSeconds = (7.0 +
            widget.item.answers.length * 1.0 +
            textLen * 0.025)
        .clamp(9.0, 16.0);
    return Duration(milliseconds: (baseSeconds * 1000).round());
  }

  @override
  void initState() {
    super.initState();
    _timerController = AnimationController(
      vsync: this,
      duration: _calculatedDuration,
    );

    _timerController.addListener(() {
      if (widget.isCurrent && !_isAnswered && !widget.isPaused) {
        final progress = (1.0 - _timerController.value).clamp(0.0, 1.0);
        final remainingSec = (_timerController.duration != null)
            ? (progress * _timerController.duration!.inMilliseconds / 1000).ceil()
            : 0;
        widget.onTimerTick?.call(progress, remainingSec);

        // Тиканье таймера только в последние 5 секунд (5, 4, 3, 2, 1)
        // Управляется настройкой "Звуки" в настройках, независимо от озвучки
        if (_lastTickedSecond != remainingSec) {
          _lastTickedSecond = remainingSec;
          if (remainingSec > 0 && remainingSec <= 5) {
            SoundEffectsService.instance.playTick();
          }
        }
      }
    });

    if (widget.initialSelectedAnswerIndex != null) {
      _selectedAnswerIndex = widget.initialSelectedAnswerIndex;
      _isAnswered = true;
    }

    _timerController.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_isAnswered && mounted) {
        _handleTimeExpired();
      }
    });

    if (widget.isCurrent) {
      if (!_isAnswered) {
        _startCard();
      } else {
        widget.onAnswerStateChanged?.call(
          true,
          _selectedAnswerIndex == widget.item.correctAnswerIndex,
        );
      }
    }
  }

  @override
  void didUpdateWidget(FeedCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSelectedAnswerIndex != null && !_isAnswered) {
      _selectedAnswerIndex = widget.initialSelectedAnswerIndex;
      _isAnswered = true;
      _timerController.stop();
    }

    if (!oldWidget.isCurrent && widget.isCurrent) {
      if (!_isAnswered) {
        _startCard();
      } else {
        widget.onAnswerStateChanged?.call(
          true,
          _selectedAnswerIndex == widget.item.correctAnswerIndex,
        );
      }
    } else if (oldWidget.isCurrent && !widget.isCurrent) {
      _stopCard();
    }

    if (oldWidget.isPaused != widget.isPaused) {
      if (widget.isPaused) {
        _timerController.stop();
        TtsService.instance.stop();
      } else if (widget.isCurrent && !_isAnswered) {
        _timerController.forward();
      }
    }

    if (oldWidget.isSoundEnabled != widget.isSoundEnabled && widget.isCurrent) {
      if (widget.isSoundEnabled && !_isAnswered) {
        _playTts();
      } else {
        TtsService.instance.stop();
      }
    }
  }

  void _startCard() {
    if (!_isAnswered) {
      _lastTickedSecond = null;
      _timerController.duration = _calculatedDuration;
      _timerController.forward(from: 0.0);
      if (widget.isSoundEnabled) {
        _playTts();
      }
    }
  }

  void _stopCard() {
    _timerController.stop();
    _autoAdvanceTimer?.cancel();
    TtsService.instance.stop();
  }

  Future<void> _playTts() async {
    if (!widget.isCurrent || _isAnswered || !widget.isSoundEnabled) return;
    await TtsService.instance.speakOrPlayFeedItem(
      rawQuestionId: widget.item.rawQuestionId,
      question: widget.item.questionText,
      answers: widget.item.answers,
    );
  }



  void _handleTimeExpired() {
    if (_isAnswered) return;
    HapticFeedbackHelper.error();
    SoundEffectsService.instance.playIncorrect();

    setState(() {
      _isAnswered = true;
      _selectedAnswerIndex = -1; // timed out
    });
    widget.onAnswerRecorded?.call(-1);
    widget.onAnswerStateChanged?.call(true, false);
    _saveProgress(isCorrect: false, selectedIndex: -1);

    _autoAdvanceTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted && widget.isCurrent) {
        widget.onAutoNext();
      }
    });
  }

  void _onAnswerSelected(int index) {
    if (_isAnswered) return;
    _timerController.stop();
    TtsService.instance.stop();

    final isCorrect = index == widget.item.correctAnswerIndex;
    if (isCorrect) {
      HapticFeedbackHelper.success();
      SoundEffectsService.instance.playCorrect();
    } else {
      HapticFeedbackHelper.error();
      SoundEffectsService.instance.playIncorrect();
    }

    setState(() {
      _selectedAnswerIndex = index;
      _isAnswered = true;
    });

    widget.onAnswerRecorded?.call(index);
    widget.onAnswerStateChanged?.call(true, isCorrect);
    _saveProgress(isCorrect: isCorrect, selectedIndex: index);
    unawaited(PremiumService.instance.recordCardCompleted());

    final delay = isCorrect
        ? const Duration(milliseconds: 650)
        : const Duration(milliseconds: 700);

    _autoAdvanceTimer = Timer(delay, () {
      if (mounted && widget.isCurrent) {
        widget.onAutoNext();
      }
    });
  }

  Future<void> _saveProgress({required bool isCorrect, required int selectedIndex}) async {
    final rawId = widget.item.rawQuestionId;
    if (rawId == null) return;
    try {
      final category = ref.read(appSettingsProvider).ticketCategory;
      final ds = ref.read(progressDataSourceProvider);
      await ds.saveAnswer(
        questionId: rawId,
        isCorrect: isCorrect,
        selectedAnswerIndex: selectedIndex,
        category: category,
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _timerController.stop();
    _autoAdvanceTimer?.cancel();
    _timerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = AppColors.of(context);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is OverscrollNotification) {
          // User dragged past bottom edge -> Next
          if (notification.overscroll > 10 && widget.isCurrent) {
            widget.onAutoNext();
            return true;
          }
          // User dragged past top edge -> Previous
          if (notification.overscroll < -10 && widget.isCurrent) {
            widget.onPrevious();
            return true;
          }
        } else if (notification is ScrollUpdateNotification) {
          // Scrolled to bottom and pulling upward -> Next
          if (_scrollController.hasClients &&
              _scrollController.position.pixels >=
                  _scrollController.position.maxScrollExtent &&
              notification.scrollDelta != null &&
              notification.scrollDelta! > 14 &&
              widget.isCurrent) {
            widget.onAutoNext();
            return true;
          }
          // Scrolled to top and pulling downward -> Previous
          if (_scrollController.hasClients &&
              _scrollController.position.pixels <=
                  _scrollController.position.minScrollExtent &&
              notification.scrollDelta != null &&
              notification.scrollDelta! < -14 &&
              widget.isCurrent) {
            widget.onPrevious();
            return true;
          }
        }
        return false;
      },
      child: SingleChildScrollView(
        controller: _scrollController,
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.only(
          left: AppDimensions.screenPadding,
          right: AppDimensions.screenPadding,
          top: MediaQuery.paddingOf(context).top + 10,
          bottom: 84,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Top Controls Header Row (Swipes with the card)
            _buildTopHeaderRow(colors),
            const SizedBox(height: AppDimensions.spacingM),

            // 2. Question / Sign Image (Clean, no card background)
            if (widget.item.imagePath != null) ...[
              Center(
                child: widget.item.isSvgImage
                    ? SvgPicture.asset(
                        widget.item.imagePath!,
                        height: 160,
                        fit: BoxFit.contain,
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(
                          AppDimensions.smallRadius,
                        ),
                        child: QuestionImage(
                          assetPath: widget.item.imagePath!,
                          height: 190,
                          fit: BoxFit.contain,
                          zoomable: true,
                        ),
                      ),
              ),
              const SizedBox(height: AppDimensions.spacingM),
            ],

            // Question Text
            Text(
              widget.item.questionText,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colors.primaryText,
                height: 1.35,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingL),

            // Answer Options (Exact Training Screen Clean Flat Style)
            ...List.generate(widget.item.answers.length, (idx) {
              final answerText = widget.item.answers[idx];
              return _buildTrainingStyleAnswerOption(idx, answerText, colors);
            }),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeaderRow(AppThemeColors colors) {
    return Row(
      children: [
        if (widget.item.badgeText != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: widget.item.isAiSmart
                  ? colors.cardBackground
                  : colors.lightAccent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.item.isAiSmart) ...[
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 13,
                    color: colors.premiumAmber,
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  widget.item.badgeText!,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: widget.item.isAiSmart
                        ? colors.premiumAmber
                        : colors.accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],

        if (_isAnswered) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: _selectedAnswerIndex == widget.item.correctAnswerIndex
                  ? colors.greenLight
                  : colors.redLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _selectedAnswerIndex == widget.item.correctAnswerIndex
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  size: 13,
                  color: _selectedAnswerIndex == widget.item.correctAnswerIndex
                      ? colors.green
                      : colors.red,
                ),
                const SizedBox(width: 4),
                Text(
                  _selectedAnswerIndex == widget.item.correctAnswerIndex
                      ? 'Верно'
                      : 'Ошибка',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _selectedAnswerIndex == widget.item.correctAnswerIndex
                        ? colors.green
                        : colors.red,
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          AnimatedBuilder(
            animation: _timerController,
            builder: (context, _) {
              final progress = (1.0 - _timerController.value).clamp(0.0, 1.0);
              final remaining = (_timerController.duration != null)
                  ? (progress * _timerController.duration!.inMilliseconds / 1000).ceil()
                  : 0;
              final isUrgent = remaining <= 3;
              final bg = isUrgent ? colors.redLight : colors.lightAccent;
              final fg = isUrgent ? colors.red : colors.accent;
              return CustomPaint(
                foregroundPainter: _RRectProgressBorderPainter(
                  progress: progress,
                  color: fg,
                  strokeWidth: 2.0,
                  radius: 10.0,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined, size: 13, color: fg),
                      const SizedBox(width: 4),
                      Text(
                        '$remaining с',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: fg,
                          fontFamily: 'Onest',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],

        const Spacer(),

        ListenableBuilder(
          listenable: PremiumService.instance,
          builder: (context, _) {
            final isPrem = PremiumService.instance.isPremium;
            final remaining = PremiumService.instance.remainingFreeCards;
            final limit = PremiumService.instance.dailyFreeLimit;

            final Color badgeBg;
            final Color badgeTextColor;
            final String badgeText;

            if (isPrem) {
              badgeBg = const Color(0xFF2BC280);
              badgeTextColor = Colors.white;
              badgeText = 'PRO';
            } else if (remaining > 0) {
              badgeBg = const Color(0xFFFFA53C);
              badgeTextColor = Colors.white;
              badgeText = '$remaining из $limit';
            } else {
              badgeBg = const Color(0xFFED4621);
              badgeTextColor = Colors.white;
              badgeText = '0 из $limit';
            }

            return GestureDetector(
              onTap: () => PremiumPaywallSheet.show(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: badgeTextColor,
                    fontFamily: 'Onest',
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTrainingStyleAnswerOption(
    int index,
    String text,
    AppThemeColors colors,
  ) {
    Color backgroundColor;
    Color textColor;
    final isCorrect = index == widget.item.correctAnswerIndex;
    final isSelected = index == _selectedAnswerIndex;

    if (_isAnswered) {
      if (isCorrect) {
        backgroundColor = colors.green;
        textColor = AppColors.white;
      } else if (isSelected) {
        backgroundColor = colors.red;
        textColor = AppColors.white;
      } else {
        backgroundColor = colors.gray;
        textColor = colors.secondaryText;
      }
    } else {
      backgroundColor = colors.cardBackground;
      textColor = colors.primaryText;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppDimensions.spacingM),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isAnswered ? null : () => _onAnswerSelected(index),
          borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
          child: Container(
            padding: const EdgeInsets.all(AppDimensions.spacingL),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _isAnswered
                        ? (isCorrect || isSelected
                            ? AppColors.white.withValues(alpha: 0.28)
                            : colors.gray)
                        : colors.gray,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: anim,
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: _isAnswered && isCorrect
                          ? const Icon(
                              Icons.check_rounded,
                              key: ValueKey('feed_answer_check'),
                              color: AppColors.white,
                              size: 16,
                            )
                          : _isAnswered && isSelected
                              ? const Icon(
                                  Icons.close_rounded,
                                  key: ValueKey('feed_answer_close'),
                                  color: AppColors.white,
                                  size: 16,
                                )
                              : Text(
                                  '${index + 1}',
                                  key: ValueKey('feed_answer_num_${index + 1}'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: colors.secondaryText,
                                  ),
                                ),
                    ),
                  ),
                ),
                const SizedBox(width: AppDimensions.spacingM),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                      height: 1.35,
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

class _RRectProgressBorderPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;
  final double radius;

  _RRectProgressBorderPainter({
    required this.progress,
    required this.color,
    this.strokeWidth = 2.0,
    this.radius = 10.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final rect = Offset.zero & size;
    final insetRect = rect.deflate(strokeWidth / 2);
    final r = (radius - strokeWidth / 2).clamp(2.0, radius);

    // Движущаяся по контуру обводка по часовой стрелке от верхнего центра
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    final path = Path();
    final topCenter = Offset(insetRect.center.dx, insetRect.top);
    path.moveTo(topCenter.dx, topCenter.dy);
    // Верхняя правая часть
    path.lineTo(insetRect.right - r, insetRect.top);
    path.arcToPoint(
      Offset(insetRect.right, insetRect.top + r),
      radius: Radius.circular(r),
      clockwise: true,
    );
    // Правая сторона
    path.lineTo(insetRect.right, insetRect.bottom - r);
    path.arcToPoint(
      Offset(insetRect.right - r, insetRect.bottom),
      radius: Radius.circular(r),
      clockwise: true,
    );
    // Нижняя сторона
    path.lineTo(insetRect.left + r, insetRect.bottom);
    path.arcToPoint(
      Offset(insetRect.left, insetRect.bottom - r),
      radius: Radius.circular(r),
      clockwise: true,
    );
    // Левая сторона
    path.lineTo(insetRect.left, insetRect.top + r);
    path.arcToPoint(
      Offset(insetRect.left + r, insetRect.top),
      radius: Radius.circular(r),
      clockwise: true,
    );
    // Замыкание в верхний центр
    path.lineTo(topCenter.dx, topCenter.dy);

    for (final metric in path.computeMetrics()) {
      final totalLength = metric.length;
      final activeLength = (totalLength * progress.clamp(0.0, 1.0));
      final extractPath = metric.extractPath(0, activeLength);
      canvas.drawPath(extractPath, progressPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RRectProgressBorderPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.radius != radius;
  }
}
