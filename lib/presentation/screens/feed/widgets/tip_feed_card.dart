import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/data/models/feed_item.dart';
import 'package:pdd_app/data/services/sound_effects_service.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/data/sources/driver_tips_data.dart';

class TipFeedCard extends StatefulWidget {
  final FeedItem item;
  final bool isCurrent;
  final VoidCallback onAutoNext;
  final VoidCallback onPrevious;
  final void Function(double progress, int remainingSeconds)? onTimerTick;

  const TipFeedCard({
    super.key,
    required this.item,
    required this.isCurrent,
    required this.onAutoNext,
    required this.onPrevious,
    this.onTimerTick,
  });

  @override
  State<TipFeedCard> createState() => _TipFeedCardState();
}

class _TipFeedCardState extends State<TipFeedCard>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;

  final ScrollController _scrollController = ScrollController();
  late AnimationController _timerController;
  int? _lastTickedSecond;

  static const Duration _tipDuration = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _timerController = AnimationController(
      vsync: this,
      duration: _tipDuration,
    );

    _timerController.addListener(() {
      if (widget.isCurrent) {
        final progress = (1.0 - _timerController.value).clamp(0.0, 1.0);
        final remainingSec = (progress * 15).ceil();
        widget.onTimerTick?.call(progress, remainingSec);

        // Sound effect tick during the last 5 seconds (5, 4, 3, 2, 1)
        if (remainingSec > 0 && remainingSec <= 5 && _lastTickedSecond != remainingSec) {
          _lastTickedSecond = remainingSec;
          SoundEffectsService.instance.playTick();
        }
      }
    });

    _timerController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted && widget.isCurrent) {
        widget.onAutoNext();
      }
    });

    if (widget.isCurrent) {
      TtsService.instance.stop().ignore();
      _startTimer();
    }
  }

  void _startTimer() {
    _lastTickedSecond = null;
    _timerController.forward(from: 0.0);
  }

  void _stopTimer() {
    _timerController.stop();
  }

  @override
  void didUpdateWidget(TipFeedCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isCurrent && widget.isCurrent) {
      TtsService.instance.stop().ignore();
      _startTimer();
    } else if (oldWidget.isCurrent && !widget.isCurrent) {
      _stopTimer();
    }
  }

  @override
  void dispose() {
    _timerController.stop();
    _timerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  IconData _resolveTipIcon(String iconKey) {
    switch (iconKey.toLowerCase()) {
      case 'timer':
        return Icons.timer_outlined;
      case 'water':
        return Icons.water_drop_rounded;
      case 'visibility':
      case 'mirrors':
        return Icons.visibility_rounded;
      case 'roundabout':
        return Icons.change_circle_rounded;
      case 'car_drive':
      case 'car_skid':
        return Icons.directions_car_filled_rounded;
      case 'stop_sign':
        return Icons.pan_tool_rounded;
      case 'truck':
        return Icons.local_shipping_rounded;
      case 'slope':
        return Icons.trending_down_rounded;
      case 'traffic_light':
        return Icons.traffic_rounded;
      case 'ice':
        return Icons.ac_unit_rounded;
      case 'turn_left':
        return Icons.turn_left_rounded;
      case 'turn_right':
        return Icons.turn_right_rounded;
      case 'blind_spot':
        return Icons.remove_red_eye_rounded;
      case 'pedestrian':
        return Icons.directions_walk_rounded;
      case 'wind':
        return Icons.air_rounded;
      case 'parking_icon':
        return Icons.local_parking_rounded;
      case 'fog':
        return Icons.cloud_queue_rounded;
      case 'hazard_triangle':
        return Icons.warning_amber_rounded;
      case 'rest':
        return Icons.coffee_rounded;
      default:
        return Icons.lightbulb_rounded;
    }
  }


  Widget _buildFallbackCircleIcon(
    IconData tipIcon,
    Color bg,
    Color fg,
  ) {
    return Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(
          color: fg.withValues(alpha: 0.25),
          width: 2,
        ),
      ),
      child: Center(
        child: Icon(
          tipIcon,
          size: 50,
          color: fg,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = AppColors.of(context);

    final tip = widget.item.driverTip ??
        DriverTip(
          id: widget.item.id,
          title: widget.item.questionText,
          description: widget.item.explanation ?? '',
          category: 'safety',
          iconKey: 'lightbulb',
        );

    final tipIcon = _resolveTipIcon(tip.iconKey);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is OverscrollNotification) {
          if (notification.overscroll > 10 && widget.isCurrent) {
            widget.onAutoNext();
            return true;
          }
          if (notification.overscroll < -10 && widget.isCurrent) {
            widget.onPrevious();
            return true;
          }
        } else if (notification is ScrollUpdateNotification) {
          if (_scrollController.hasClients &&
              _scrollController.position.pixels >=
                  _scrollController.position.maxScrollExtent &&
              notification.scrollDelta != null &&
              notification.scrollDelta! > 14 &&
              widget.isCurrent) {
            widget.onAutoNext();
            return true;
          }
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
            // Top Header Row (Swipes with the card)
            Row(
              children: [
                AnimatedBuilder(
                  animation: _timerController,
                  builder: (context, _) {
                    final progress = (1.0 - _timerController.value).clamp(0.0, 1.0);
                    final remaining = (progress * 15).ceil();
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
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lightbulb_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Совет',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingM),

            // Single Unified Card Container (No shadows, image + text combined on one card)
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: colors.cardBackground,
                borderRadius: BorderRadius.circular(
                  AppDimensions.cardRadius,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Full-Width Hero Graphic Image Container
                  if (tip.imagePath.isNotEmpty)
                    AspectRatio(
                      aspectRatio: 1.0,
                      child: Image.asset(
                        tip.imagePath,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: _buildFallbackCircleIcon(
                            tipIcon,
                            colors.lightAccent,
                            colors.accent,
                          ),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: _buildFallbackCircleIcon(
                        tipIcon,
                        colors.lightAccent,
                        colors.accent,
                      ),
                    ),

                  // Tip Text Details inside the same card
                  Padding(
                    padding: const EdgeInsets.all(AppDimensions.spacingXL),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title is the punchy tip directly
                        Text(
                          tip.title,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: colors.primaryText,
                            height: 1.3,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Short 1-2 sentence description
                        Text(
                          tip.description,
                          style: TextStyle(
                            fontSize: 15.5,
                            color: colors.secondaryText,
                            height: 1.5,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
          ],
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
