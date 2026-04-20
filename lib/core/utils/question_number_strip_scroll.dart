import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';

/// Horizontal chip: 32×32 + 4px gap → stride 36.
const double kQuestionNumberStripStride = 36;
const double kQuestionNumberStripTile = 32;

/// Scrolls a horizontal [ListView] so [currentIndex] stays visible, centered when possible.
void scheduleScrollQuestionStripToCurrent({
  required ScrollController controller,
  required int currentIndex,
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!controller.hasClients) return;
    final position = controller.position;
    final viewport = position.viewportDimension;
    final maxScroll = position.maxScrollExtent;
    final pad = AppDimensions.screenPadding;
    final itemLeading = pad + currentIndex * kQuestionNumberStripStride;
    final itemCenter = itemLeading + kQuestionNumberStripTile / 2;
    final target = (itemCenter - viewport / 2).clamp(0.0, maxScroll);
    controller.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  });
}
