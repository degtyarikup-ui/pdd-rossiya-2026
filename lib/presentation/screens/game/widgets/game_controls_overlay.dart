import 'package:pdd_app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/presentation/screens/game/controllers/game_controller.dart';

class GameControlsOverlay extends StatefulWidget {
  final GameState state;
  final ValueChanged<bool> onGasChanged;
  final ValueChanged<String> onSwitchLane;
  final ValueChanged<int>? onSteering;
  final ValueChanged<bool>? onBrake;

  const GameControlsOverlay({
    super.key,
    required this.state,
    required this.onGasChanged,
    required this.onSwitchLane,
    this.onSteering,
    this.onBrake,
  });

  @override
  State<GameControlsOverlay> createState() => _GameControlsOverlayState();
}

class _GameControlsOverlayState extends State<GameControlsOverlay> {
  final _heldDirections = <int>[];
  bool _disposing = false;

  void _steer(int direction, bool held) {
    if (_disposing) return;
    _heldDirections.remove(direction);
    if (held && widget.state.controlsEnabled) _heldDirections.add(direction);
    widget.onSteering?.call(
      widget.state.controlsEnabled && _heldDirections.isNotEmpty
          ? _heldDirections.last
          : 0,
    );
  }

  @override
  void didUpdateWidget(covariant GameControlsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.state.controlsEnabled) _heldDirections.clear();
  }

  @override
  void dispose() {
    _disposing = true;
    if (_heldDirections.isNotEmpty) widget.onSteering?.call(0);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final buttonWidth = ((constraints.maxWidth - 122) / 2).clamp(
              48.0,
              74.0,
            );
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _LaneButton(
                      width: buttonWidth,
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: appL10n.gameLeft,
                      onHold: widget.state.controlsEnabled
                          ? (held) => _steer(1, held)
                          : null,
                      onTap: null,
                    ),
                    const SizedBox(width: 10),
                    _LaneButton(
                      width: buttonWidth,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: appL10n.gameRight,
                      onHold: widget.state.controlsEnabled
                          ? (held) => _steer(-1, held)
                          : null,
                      onTap: null,
                    ),
                  ],
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Brake while moving; from a standstill it is reverse gear.
                    _LaneButton(
                      key: const ValueKey('game-brake'),
                      width: 100,
                      icon: const _BrakePedalIcon(),
                      label: appL10n.gameBrake,
                      backgroundColor: AppThemeColors.dark.cardBackground,
                      iconColor: AppColors.white,
                      activeColor: colors.red,
                      onHold: widget.state.controlsEnabled
                          ? (held) => widget.onBrake?.call(held)
                          : null,
                      onTap: null,
                    ),
                    const SizedBox(height: 10),
                    _GasPedal(
                      speedKmH: widget.state.speedKmH,
                      enabled: widget.state.controlsEnabled,
                      onGasChanged: widget.onGasChanged,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LaneButton extends StatefulWidget {
  final Widget icon;
  final String label;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onHold;
  final Color? activeColor;
  final Color? backgroundColor;
  final Color? iconColor;
  final double width;

  const _LaneButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.onHold,
    this.activeColor,
    this.backgroundColor,
    this.iconColor,
    this.width = 74,
  });

  @override
  State<_LaneButton> createState() => _LaneButtonState();
}

class _LaneButtonState extends State<_LaneButton> {
  int? _pointer;

  @override
  void didUpdateWidget(covariant _LaneButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onHold == null && _pointer != null) {
      _pointer = null;
      oldWidget.onHold?.call(false);
    }
  }

  @override
  void dispose() {
    if (_pointer != null) widget.onHold?.call(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Listener(
      onPointerDown: (event) {
        if (widget.onHold == null || _pointer != null) return;
        setState(() => _pointer = event.pointer);
        widget.onHold!(true);
      },
      onPointerUp: (event) {
        if (_pointer != event.pointer) return;
        setState(() => _pointer = null);
        widget.onHold?.call(false);
      },
      onPointerCancel: (event) {
        if (_pointer != event.pointer) return;
        setState(() => _pointer = null);
        widget.onHold?.call(false);
      },
      child: SizedBox(
        width: widget.width,
        height: 76,
        child: Material(
          color: _pointer != null
              ? (widget.activeColor ?? colors.accent)
              : (widget.backgroundColor ?? colors.cardBackground),
          borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
          child: InkWell(
            onTap: widget.onHold == null ? widget.onTap : null,
            borderRadius: BorderRadius.circular(AppDimensions.smallRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              child: Semantics(
                label: widget.label,
                button: true,
                child: Center(
                  child: IconTheme(
                    data: IconThemeData(
                      size: 30,
                      color: _pointer != null
                          ? AppColors.white
                          : widget.onHold == null
                          ? colors.secondaryText
                          : (widget.iconColor ??
                                widget.activeColor ??
                                colors.accent),
                    ),
                    child: widget.icon,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrakePedalIcon extends StatelessWidget {
  const _BrakePedalIcon();

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(44, 44),
    painter: _BrakePedalPainter(IconTheme.of(context).color ?? AppColors.white),
  );
}

class _BrakePedalPainter extends CustomPainter {
  final Color color;

  const _BrakePedalPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 44, size.height / 44);
    canvas.translate(22, 22);
    canvas.rotate(-0.16);
    canvas.translate(-22, -22);
    final outline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Pedal arm and wide rubber pad, with three raised grip ribs.
    canvas.drawPath(
      Path()
        ..moveTo(22, 27)
        ..lineTo(22, 36)
        ..lineTo(30, 40),
      outline,
    );
    final pad = RRect.fromRectAndRadius(
      const Rect.fromLTWH(7, 4, 30, 24),
      const Radius.circular(6),
    );
    canvas.drawRRect(pad, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawRRect(pad, outline);
    for (final y in [11.0, 16.0, 21.0]) {
      canvas.drawLine(Offset(14, y), Offset(30, y), outline);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BrakePedalPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _GasPedal extends StatefulWidget {
  final int speedKmH;
  final bool enabled;
  final ValueChanged<bool> onGasChanged;

  const _GasPedal({
    required this.speedKmH,
    required this.enabled,
    required this.onGasChanged,
  });

  @override
  State<_GasPedal> createState() => _GasPedalState();
}

class _GasPedalState extends State<_GasPedal> {
  bool _isPressed = false;
  int? _pointer;

  void _setPressed(bool val) {
    if (_isPressed != val) {
      setState(() => _isPressed = val);
      widget.onGasChanged(val);
    }
  }

  @override
  void didUpdateWidget(covariant _GasPedal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _isPressed) {
      _pointer = null;
      _isPressed = false;
      widget.onGasChanged(false);
    }
  }

  @override
  void dispose() {
    if (_isPressed) widget.onGasChanged(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    // A held pedal is not a tap: normal finger drift must not let a competing
    // gesture recognizer cancel acceleration. Track the original pointer until
    // it is lifted/cancelled, including when a second finger steers.
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        if (!widget.enabled || _pointer != null) return;
        _pointer = event.pointer;
        _setPressed(true);
      },
      onPointerUp: (event) {
        if (event.pointer != _pointer) return;
        _pointer = null;
        _setPressed(false);
      },
      onPointerCancel: (event) {
        if (event.pointer != _pointer) return;
        _pointer = null;
        _setPressed(false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: _isPressed ? colors.accent : colors.cardBackground,
          shape: BoxShape.circle,
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.speed_rounded,
                  size: 26,
                  color: _isPressed ? AppColors.white : colors.accent,
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.speedKmH}',
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: _isPressed ? AppColors.white : colors.primaryText,
                    height: 1.1,
                  ),
                ),
                Text(
                  _isPressed ? appL10n.gameGas : appL10n.gameSpeedUnit,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: _isPressed ? AppColors.white : colors.secondaryText,
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
