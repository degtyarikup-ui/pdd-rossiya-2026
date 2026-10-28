import 'package:flutter/material.dart';

/// Shared width limits. Compact screens keep their existing 480px layout;
/// reading/form pages stay narrow while catalogues can use the wider canvas.
class AppContentFrame extends StatelessWidget {
  const AppContentFrame({
    super.key,
    this.maxWidth = readingWidth,
    required this.child,
  });

  static const compactWidth = 480.0;
  static const expandedBreakpoint = 600.0;
  static const readingWidth = 720.0;
  static const catalogueWidth = 1040.0;
  static const canvasWidth = 1200.0;
  static const desktopContentWidth = 1120.0;

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final limit = constraints.maxWidth < expandedBreakpoint
            ? compactWidth
            : maxWidth;
        // Always keep the same widget ancestry across resizes so child state,
        // PageViews and timers survive a change of layout.
        return Align(
          alignment: Alignment.topCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: limit),
            child: SizedBox(width: double.infinity, child: child),
          ),
        );
      },
    );
  }
}
