import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/data/models/feed_item.dart';
import 'package:pdd_app/data/services/tts_service.dart';
import 'package:pdd_app/data/sources/driver_tips_data.dart';

class TipFeedCard extends StatefulWidget {
  final FeedItem item;
  final bool isCurrent;
  final VoidCallback onAutoNext;
  final VoidCallback onPrevious;

  const TipFeedCard({
    super.key,
    required this.item,
    required this.isCurrent,
    required this.onAutoNext,
    required this.onPrevious,
  });

  @override
  State<TipFeedCard> createState() => _TipFeedCardState();
}

class _TipFeedCardState extends State<TipFeedCard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.isCurrent) {
      TtsService.instance.stop().ignore();
    }
  }

  @override
  void didUpdateWidget(TipFeedCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isCurrent && widget.isCurrent) {
      TtsService.instance.stop().ignore();
    }
  }

  @override
  void dispose() {
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

  String _resolveCategoryName(String category) {
    switch (category) {
      case 'safety':
        return 'Безопасность';
      case 'weather':
        return 'Погода';
      case 'winter':
        return 'Зимняя езда';
      case 'rules':
        return 'ПДД';
      case 'highway':
        return 'Трасса';
      case 'maneuver':
        return 'Маневры';
      case 'mirrors':
        return 'Обзор';
      case 'comfort':
        return 'Комфорт';
      case 'parking':
        return 'Парковка';
      default:
        return 'ПДД 2026';
    }
  }

  Widget _buildFallbackCircleIcon(
    IconData tipIcon,
    Color yellowBadgeBg,
    Color yellowBadgeText,
  ) {
    return Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(
        color: yellowBadgeBg,
        shape: BoxShape.circle,
        border: Border.all(
          color: yellowBadgeText.withValues(alpha: 0.25),
          width: 2,
        ),
      ),
      child: Center(
        child: Icon(
          tipIcon,
          size: 50,
          color: yellowBadgeText,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final tip = widget.item.driverTip ??
        DriverTip(
          id: widget.item.id,
          title: widget.item.questionText,
          description: widget.item.explanation ?? '',
          category: 'safety',
          iconKey: 'lightbulb',
        );

    final tipIcon = _resolveTipIcon(tip.iconKey);
    final categoryName = _resolveCategoryName(tip.category);

    // Rich, vibrant brighter Yellow / Amber palette for the Tip badge
    final yellowBadgeBg = isDark ? const Color(0xFF422006) : const Color(0xFFFEF08A);
    final yellowBadgeText = isDark ? const Color(0xFFFACC15) : const Color(0xFFCA8A04);

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
        padding: const EdgeInsets.only(
          left: AppDimensions.screenPadding,
          right: AppDimensions.screenPadding,
          top: 14,
          bottom: 84,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                        errorBuilder: (_, __, ___) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: _buildFallbackCircleIcon(
                            tipIcon,
                            yellowBadgeBg,
                            yellowBadgeText,
                          ),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: _buildFallbackCircleIcon(
                        tipIcon,
                        yellowBadgeBg,
                        yellowBadgeText,
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
