import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/layout/app_content_frame.dart';

/// App canvas. Individual screens choose their readable/content width with
/// [AppContentFrame]; phones retain the original layout and dimensions.
class AppMaxWidthFrame extends StatelessWidget {
  final Widget? child;

  static const double maxContentWidth = AppContentFrame.canvasWidth;

  const AppMaxWidthFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    // Keep Navigator at the same element path during rotation. A conditional
    // wrapper here would dispose routes, session state and timers on resize.
    final colors = AppColors.of(context);
    return ColoredBox(
      color: colors.isDark ? Colors.black : colors.divider,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width < AppContentFrame.expandedBreakpoint
                ? AppContentFrame.compactWidth
                : maxContentWidth,
          ),
          child: ClipRect(
            child: Material(
              color: colors.background,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final media = MediaQuery.of(context);
                  final gutter = (media.size.width - constraints.maxWidth) / 2;
                  EdgeInsets inside(EdgeInsets insets) => insets.copyWith(
                    left: (insets.left - gutter).clamp(0, double.infinity),
                    right: (insets.right - gutter).clamp(0, double.infinity),
                  );
                  return MediaQuery(
                    data: media.copyWith(
                      size: Size(constraints.maxWidth, media.size.height),
                      padding: inside(media.padding),
                      viewPadding: inside(media.viewPadding),
                      systemGestureInsets: inside(media.systemGestureInsets),
                    ),
                    child: child ?? const SizedBox.shrink(),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
