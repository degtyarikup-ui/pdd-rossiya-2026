import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/models/feed_item.dart';
import 'package:pdd_app/data/repositories/providers.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';
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

  const FeedCard({
    super.key,
    required this.item,
    required this.isCurrent,
    required this.isSoundEnabled,
    this.initialSelectedAnswerIndex,
    this.onAnswerRecorded,
    required this.onToggleSound,
    required this.onAutoNext,
    required this.onPrevious,
  });

  @override
  ConsumerState<FeedCard> createState() => _FeedCardState();
}

class _FeedCardState extends ConsumerState<FeedCard>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late AnimationController _timerController;
  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;
  final ScrollController _scrollController = ScrollController();
  int? _selectedAnswerIndex;
  bool _isAnswered = false;
  bool _isFavorite = false;
  Timer? _autoAdvanceTimer;

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

    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    _bounceAnimation = Tween<double>(begin: 0.0, end: -7.0).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );

    if (widget.initialSelectedAnswerIndex != null) {
      _selectedAnswerIndex = widget.initialSelectedAnswerIndex;
      _isAnswered = true;
    }

    _timerController.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_isAnswered && mounted) {
        _handleTimeExpired();
      }
    });

    _checkFavorite();

    if (widget.isCurrent && !_isAnswered) {
      _startCard();
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
      }
    } else if (oldWidget.isCurrent && !widget.isCurrent) {
      _stopCard();
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
    final audioDuration = await TtsService.instance.speakOrPlayFeedItem(
      rawQuestionId: widget.item.rawQuestionId,
      question: widget.item.questionText,
      answers: widget.item.answers,
    );

    if (!widget.isCurrent || _isAnswered || !mounted) {
      TtsService.instance.stop().ignore();
      return;
    }

    if (audioDuration != null) {
      final dynamicTotal = audioDuration + const Duration(milliseconds: 5000);
      _timerController.duration = dynamicTotal;
      _timerController.forward(from: 0.0);
    }
  }

  Future<void> _checkFavorite() async {
    final rawId = widget.item.rawQuestionId;
    if (rawId == null) return;
    try {
      final category = ref.read(appSettingsProvider).ticketCategory;
      final ds = ref.read(progressDataSourceProvider);
      final isFav = await ds.isFavorite(rawId, category);
      if (mounted) setState(() => _isFavorite = isFav);
    } catch (_) {}
  }

  Future<void> _toggleFavorite() async {
    final rawId = widget.item.rawQuestionId;
    if (rawId == null) {
      HapticFeedbackHelper.tap();
      setState(() => _isFavorite = !_isFavorite);
      return;
    }
    HapticFeedbackHelper.success();
    final category = ref.read(appSettingsProvider).ticketCategory;
    final ds = ref.read(progressDataSourceProvider);
    await ds.toggleFavorite(rawId, category);
    final isFav = await ds.isFavorite(rawId, category);
    if (mounted) setState(() => _isFavorite = isFav);
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
    _saveProgress(isCorrect: false, selectedIndex: -1);
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
    _saveProgress(isCorrect: isCorrect, selectedIndex: index);

    if (isCorrect) {
      _autoAdvanceTimer = Timer(const Duration(milliseconds: 650), () {
        if (mounted && widget.isCurrent) {
          widget.onAutoNext();
        }
      });
    }
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
    _timerController.dispose();
    _bounceController.dispose();
    _autoAdvanceTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = AppColors.of(context);

    return Container(
      color: colors.homeScreenBackground,
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                // 1. Top Bar (Badge, Timer Pill, Sound & Favorite Buttons)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.screenPadding,
                    vertical: AppDimensions.spacingM,
                  ),
                  child: Row(
                    children: [
                      if (widget.item.badgeText != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: colors.lightAccent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            widget.item.badgeText!,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: colors.accent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      // Digital Countdown Timer Pill
                      _buildDigitalTimerPill(colors),
                      const Spacer(),
                      // Sound Button
                      AppChromeIconButton(
                        icon: widget.isSoundEnabled
                            ? Icons.volume_up_rounded
                            : Icons.volume_off_rounded,
                        backgroundColor: widget.isSoundEnabled
                            ? colors.lightAccent
                            : colors.cardBackground,
                        iconColor: widget.isSoundEnabled
                            ? colors.accent
                            : colors.primaryText.withValues(alpha: 0.65),
                        onTap: widget.onToggleSound,
                      ),
                      const SizedBox(width: 8),
                      // Favorite Star Button
                      AppChromeIconButton(
                        icon: _isFavorite
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        backgroundColor: _isFavorite
                            ? colors.goldLightSurface
                            : colors.cardBackground,
                        iconColor: _isFavorite
                            ? colors.gold
                            : colors.primaryText.withValues(alpha: 0.65),
                        onTap: _toggleFavorite,
                      ),
                    ],
                  ),
                ),

                // 2. Question Card Body
                Expanded(
                  child: Stack(
                    children: [
                      NotificationListener<ScrollNotification>(
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
                          padding: const EdgeInsets.only(
                            left: AppDimensions.screenPadding,
                            right: AppDimensions.screenPadding,
                            bottom: 72,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Question / Sign Image (Clean, no card background)
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

                              // Explanation Card (Clean without duplicate hint)
                              if (_isAnswered &&
                                  _selectedAnswerIndex != widget.item.correctAnswerIndex &&
                                  widget.item.explanation != null &&
                                  widget.item.explanation!.isNotEmpty) ...[
                                const SizedBox(height: AppDimensions.spacingL),
                                Container(
                                  padding: const EdgeInsets.all(AppDimensions.spacingL),
                                  decoration: BoxDecoration(
                                    color: colors.cardBackground,
                                    borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.lightbulb, color: colors.gold, size: 20),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Комментарий',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: colors.primaryText,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: AppDimensions.spacingM),
                                      Text(
                                        widget.item.explanation!,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: colors.secondaryText,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),
                      // Fixed Bottom Countdown Progress Bar (Non-scrollable, Non-draggable)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _timerController,
                            builder: (context, child) {
                              final progress = (1.0 - _timerController.value).clamp(0.0, 1.0);
                              Color barColor;
                              if (_isAnswered) {
                                final isCorrect = _selectedAnswerIndex == widget.item.correctAnswerIndex;
                                barColor = isCorrect ? colors.green : colors.red;
                              } else if (progress > 0.3) {
                                barColor = colors.accent;
                              } else if (progress > 0.15) {
                                barColor = colors.gold;
                              } else {
                                barColor = colors.red;
                              }

                              return SizedBox(
                                height: 3.5,
                                child: LinearProgressIndicator(
                                  value: _isAnswered ? 1.0 : progress,
                                  backgroundColor: colors.cardBackground.withValues(alpha: 0.5),
                                  valueColor: AlwaysStoppedAnimation<Color>(barColor),
                                  minHeight: 3.5,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Fixed Bottom Floating "Свайпай ↑" Pill with Twitch / Bob Animation
            if (_isAnswered && _selectedAnswerIndex != widget.item.correctAnswerIndex)
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Center(
                  child: AnimatedBuilder(
                    animation: _bounceAnimation,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, _bounceAnimation.value),
                        child: child,
                      );
                    },
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          HapticFeedbackHelper.tap();
                          widget.onAutoNext();
                        },
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: colors.accent,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Свайпай',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              SizedBox(width: 6),
                              Icon(
                                Icons.arrow_upward_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
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

  Widget _buildDigitalTimerPill(AppThemeColors colors) {
    return AnimatedBuilder(
      animation: _timerController,
      builder: (context, _) {
        final totalSec =
            (_timerController.duration?.inMilliseconds ?? 10000) / 1000.0;
        final remainingSec =
            ((1.0 - _timerController.value) * totalSec).ceil().clamp(0, 99);

        Color timerBg;
        Color timerTextColor;
        String timerText;
        IconData timerIcon;

        if (_isAnswered) {
          final isCorrect =
              _selectedAnswerIndex == widget.item.correctAnswerIndex;
          if (isCorrect) {
            timerBg = colors.greenLight;
            timerTextColor = colors.green;
            timerText = 'Верно';
            timerIcon = Icons.check_circle_rounded;
          } else if (_selectedAnswerIndex == -1) {
            timerBg = colors.redLight;
            timerTextColor = colors.red;
            timerText = 'Время вышло';
            timerIcon = Icons.timer_off_rounded;
          } else {
            timerBg = colors.redLight;
            timerTextColor = colors.red;
            timerText = 'Ошибка';
            timerIcon = Icons.cancel_rounded;
          }
        } else {
          if (remainingSec > 5) {
            timerBg = colors.lightAccent;
            timerTextColor = colors.accent;
            timerIcon = Icons.timer_outlined;
          } else if (remainingSec > 2) {
            timerBg = colors.goldLightSurface;
            timerTextColor = colors.gold;
            timerIcon = Icons.timer_outlined;
          } else {
            timerBg = colors.redLight;
            timerTextColor = colors.red;
            timerIcon = Icons.timer_outlined;
          }
          timerText = '$remainingSec с';
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: timerBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(timerIcon, size: 14, color: timerTextColor),
              const SizedBox(width: 5),
              Text(
                timerText,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: timerTextColor,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
