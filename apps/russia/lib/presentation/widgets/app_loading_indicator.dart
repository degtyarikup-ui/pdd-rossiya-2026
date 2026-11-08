import 'package:flutter/material.dart';

import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/widgets/loading_frame_probe.dart';

/// The shared, pre-rendered 30 fps loader. Flutter decodes frames on demand;
/// there is no 3D scene, animation controller, or list of decoded frames here.
class AppLoadingIndicator extends StatefulWidget {
  const AppLoadingIndicator({super.key, this.size = 160, this.label})
    : assert(size > 0 && size < double.infinity);

  static const animationAsset =
      'assets/mascot/raster/cone-juggling-384-30.webp';
  static const posterAsset =
      'assets/mascot/raster/cone-juggling-poster-384.webp';
  static const imageProvider = AssetImage(animationAsset);

  final double size;
  final String? label;

  @override
  State<AppLoadingIndicator> createState() => _AppLoadingIndicatorState();
}

class _AppLoadingIndicatorState extends State<AppLoadingIndicator>
    with WidgetsBindingObserver {
  AppLifecycleState? _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_lifecycle != state) setState(() => _lifecycle = state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget _poster() => Image.asset(
    AppLoadingIndicator.posterAsset,
    excludeFromSemantics: true,
    fit: BoxFit.contain,
    errorBuilder: (_, _, _) => const Icon(Icons.hourglass_empty_rounded),
  );

  @override
  Widget build(BuildContext context) {
    final animate =
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled &&
        (_lifecycle == null || _lifecycle == AppLifecycleState.resumed);
    final label = widget.label ?? appL10n.appLoading;
    final content = Semantics(
      label: label,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RepaintBoundary(
              child: SizedBox.square(
                dimension: widget.size,
                child: animate
                    ? Image(
                        image: AppLoadingIndicator.imageProvider,
                        fit: BoxFit.contain,
                        excludeFromSemantics: true,
                        // The poster is replaced, never layered under alpha.
                        frameBuilder: (_, child, frame, _) =>
                            frame == null ? _poster() : child,
                        errorBuilder: (_, _, _) => _poster(),
                      )
                    : _poster(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.of(context).secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
    return loadingFrameProbeEnabled && animate
        ? LoadingFrameProbe(label: label, child: content)
        : content;
  }
}

/// A temporary input shield for actual preparation/return work. It keeps the
/// underlying route mounted and stops its tickers while the loader is visible.
class AppLoadingOverlay {
  AppLoadingOverlay._(String? label) : _label = label {
    _entry = OverlayEntry(
      opaque: true,
      builder: (context) => _visible
          ? Positioned.fill(
              child: Material(
                color: AppColors.of(context).background,
                child: BlockSemantics(
                  child: SafeArea(
                    child: Center(child: AppLoadingIndicator(label: _label)),
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  OverlayEntry? _entry;
  bool _visible = true;
  String? _label;

  static AppLoadingOverlay show(BuildContext context, {String? label}) {
    final overlay = AppLoadingOverlay._(label);
    Overlay.of(context, rootOverlay: true).insert(overlay._entry!);
    return overlay;
  }

  /// iOS keeps Flutter alive below its game window. Remove the image listener
  /// while the game is visible, then paint a return frame before hiding it.
  void setVisible(bool visible, {String? label}) {
    if (_entry == null) return;
    _visible = visible;
    if (label != null) _label = label;
    _entry!.opaque = visible;
    _entry!.markNeedsBuild();
  }

  void close() {
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }
}
