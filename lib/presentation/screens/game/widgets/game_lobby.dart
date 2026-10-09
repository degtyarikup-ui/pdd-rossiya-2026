import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/l10n/l10n.dart';
import 'package:pdd_app/presentation/screens/game/widgets/game_garage.dart';

/// The game's start screen, laid over the engine's garage scene. No cards:
/// the car stands in the middle and is browsed by swiping or the side
/// arrows; top — the (secondary) controls button, the runs in stock and the
/// record; right — round colour and rating buttons; bottom — «Start the
/// drive» with what a run is (or [blocker] when driving is not possible:
/// sign-in card, no runs left).
class GameLobby extends StatelessWidget {
  final String vehiclePaint;
  final int bestScore;

  /// The runs in stock (a tappable pill).
  final Widget runs;
  final Widget? blocker;
  final VoidCallback? onStart;

  /// Opened from a run in progress: the button continues it.
  final bool resume;

  /// Small line under «Продолжить заезд»: «Пройдено 8 из 20».
  final String? startCaption;

  /// The car on the stand: its name shows for a moment after browsing and
  /// stays, with a «Новая» badge, while the model has never been driven.
  final String? carName;
  final bool carIsNew;

  /// Null when there is only one car to choose from.
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  final VoidCallback? onColour;

  /// A finger drag on the scene turns the car (horizontal pixels).
  final ValueChanged<double>? onSpin;
  final VoidCallback? onLeaderboard;
  final VoidCallback? onControls;

  const GameLobby({
    super.key,
    required this.vehiclePaint,
    required this.bestScore,
    required this.runs,
    this.blocker,
    this.onStart,
    this.resume = false,
    this.startCaption,
    this.carName,
    this.carIsNew = false,
    this.onPrevious,
    this.onNext,
    this.onColour,
    this.onLeaderboard,
    this.onControls,
    this.onSpin,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // A round button with its caption underneath, readable over the scene.
    // A fixed-width column keeps the round buttons on one vertical line
    // whatever the caption length.
    Widget labelled(Widget button, String caption) => SizedBox(
      width: 76,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          button,
          const SizedBox(height: 4),
          // The button itself is labelled for screen readers; its caption
          // grows only a little with the system text, or the column of
          // buttons climbs over the car arrows on a small phone.
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                caption,
                style: const TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.white,
                  shadows: [Shadow(color: Color(0x99000000), blurRadius: 6)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Widget round({
      required Color color,
      required Widget icon,
      required String label,
      VoidCallback? onTap,
      double size = 56,
    }) => Semantics(
      button: true,
      label: label,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(child: icon),
          ),
        ),
      ),
    );
    Widget arrow(IconData icon, String label, VoidCallback onTap) => round(
      color: AppColors.white.withValues(alpha: 0.88),
      size: 46,
      label: label,
      onTap: () {
        HapticFeedbackHelper.select();
        onTap();
      },
      icon: Icon(icon, color: colors.accent, size: 28),
    );
    return Stack(
      children: [
        // Dragging on the scene turns the car; the arrows change it.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: (details) => onSpin?.call(details.delta.dx),
          ),
        ),
        // Top: controls (like the pause button in the drive) and the runs
        // on the left, the record in the HUD's gold pill on the right.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(
                children: [
                  if (onControls != null) ...[
                    Semantics(
                      button: true,
                      label: appL10n.gameControlsTitle,
                      child: Material(
                        color: colors.cardBackground,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          key: const ValueKey('lobby-controls'),
                          onTap: onControls,
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Icon(
                              Icons.settings_rounded,
                              size: 24,
                              color: colors.primaryText,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // Runs on the left, the record on the right; with very
                  // large text both shrink together rather than overflow.
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) => FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: box.maxWidth),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              runs,
                              const SizedBox(width: 8),
                              Semantics(
                                label: '${appL10n.gameLobbyRecord}: $bestScore',
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    9,
                                    7,
                                    11,
                                    7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.gold,
                                    borderRadius: BorderRadius.circular(90),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SvgPicture.asset(
                                        'assets/icons/game/hud_star.svg',
                                        width: 14,
                                        height: 14,
                                        colorFilter: const ColorFilter.mode(
                                          AppColors.white,
                                          BlendMode.srcIn,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${appL10n.gameLobbyRecord} $bestScore',
                                        style: const TextStyle(
                                          fontFamily: 'Onest',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.white,
                                          height: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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
          ),
        ),
        if (carName != null)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 66,
            left: 16,
            right: 16,
            child: Center(
              child: _CarTitle(
                key: ValueKey(carName),
                name: carName!,
                isNew: carIsNew,
              ),
            ),
          ),
        // Arrows either side of the car.
        if (onPrevious != null)
          Align(
            alignment: const Alignment(-0.92, -0.04),
            child: arrow(
              Icons.chevron_left_rounded,
              MaterialLocalizations.of(context).previousPageTooltip,
              onPrevious!,
            ),
          ),
        if (onNext != null)
          Align(
            alignment: const Alignment(0.92, -0.04),
            child: arrow(
              Icons.chevron_right_rounded,
              MaterialLocalizations.of(context).nextPageTooltip,
              onNext!,
            ),
          ),
        // Bottom: the start button (or the blocker), round buttons above it
        // on the right: the car's colour and the weekly rating.
        Positioned(
          left: 16,
          right: 16,
          bottom: 16 + bottomInset,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              labelled(
                round(
                  color: colors.cardBackground,
                  label:
                      '${appL10n.gameLobbyColour}: ${gamePaintName(vehiclePaint)}',
                  onTap: onColour,
                  icon: Icon(
                    Icons.palette_rounded,
                    color: colors.primaryText,
                    size: 26,
                  ),
                ),
                appL10n.gameLobbyColour,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child:
                    blocker ??
                    ConstrainedBox(
                      // Grows with the system text size instead of cutting
                      // the caption off.
                      constraints: const BoxConstraints(minHeight: 56),
                      child: ElevatedButton(
                        onPressed: onStart,
                        // 56 high with the run's progress under the title.
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 8,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              resume
                                  ? appL10n.gameLobbyContinue
                                  : appL10n.gameLobbyStart,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'Onest',
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                              ),
                            ),
                            if (startCaption != null)
                              Text(
                                startCaption!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Onest',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  height: 1.2,
                                  color: AppColors.white.withValues(
                                    alpha: 0.78,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A compact sheet of the car's available colours.
Future<String?> showGamePaintSheet(
  BuildContext context, {
  required List<String> paints,
  required String selected,
  bool showHint = false,
}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      final colors = AppColors.of(context);
      return SingleChildScrollView(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  appL10n.gameLobbyColour,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: colors.primaryText,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final paint in paints)
                      Semantics(
                        button: true,
                        selected: paint == selected,
                        label: gamePaintName(paint),
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedbackHelper.select();
                            Navigator.pop(context, paint);
                          },
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: gamePaintColors[paint],
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: paint == selected
                                    ? colors.accent
                                    : colors.divider,
                                width: paint == selected ? 3 : 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (showHint) ...[
                  const SizedBox(height: 16),
                  Text(
                    appL10n.gameLobbyColoursHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 13,
                      color: colors.secondaryText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Choice between «Простое» (arrows = lane changes and exits, the car
/// drives itself) and «Свободное» (the arrow turns the wheel while held).
Future<bool?> showGameControlsSheet(
  BuildContext context, {
  required bool simple,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      final colors = AppColors.of(context);
      Widget option({
        required bool value,
        required IconData icon,
        required String title,
        required String hint,
      }) {
        final selected = value == simple;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: selected ? colors.accentSurface10 : colors.background,
            borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context).pop(value),
              child: Semantics(
                selected: selected,
                button: true,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: selected
                              ? colors.accent
                              : colors.cardBackground,
                          borderRadius: BorderRadius.circular(
                            AppDimensions.buttonRadius,
                          ),
                        ),
                        child: Icon(
                          icon,
                          color: selected ? AppColors.white : colors.accent,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontFamily: 'Onest',
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: colors.primaryText,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              hint,
                              style: TextStyle(
                                fontFamily: 'Onest',
                                fontSize: 13,
                                height: 1.3,
                                color: colors.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        color: selected ? colors.accent : colors.gray,
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }

      return SingleChildScrollView(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
                  child: Text(
                    appL10n.gameControlsTitle,
                    style: TextStyle(
                      fontFamily: 'Onest',
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: colors.primaryText,
                    ),
                  ),
                ),
                option(
                  value: true,
                  icon: Icons.alt_route_rounded,
                  title: appL10n.gameControlsSimple,
                  hint: appL10n.gameControlsSimpleHint,
                ),
                option(
                  value: false,
                  icon: Icons.sports_esports_rounded,
                  title: appL10n.gameControlsFree,
                  hint: appL10n.gameControlsFreeHint,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// The model's name over the scene; with a «Новая» badge it stays, else it
/// fades out a moment after the car was changed.
class _CarTitle extends StatefulWidget {
  final String name;
  final bool isNew;

  const _CarTitle({super.key, required this.name, required this.isNew});

  @override
  State<_CarTitle> createState() => _CarTitleState();
}

class _CarTitleState extends State<_CarTitle> {
  bool _shown = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _shown = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _shown || widget.isNew ? 1 : 0,
        duration: const Duration(milliseconds: 400),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                widget.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.white,
                  shadows: [Shadow(color: Color(0x99000000), blurRadius: 8)],
                ),
              ),
            ),
            if (widget.isNew) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.gold,
                  borderRadius: BorderRadius.circular(90),
                ),
                child: Text(
                  appL10n.gameLobbyNewCar,
                  style: const TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: AppColors.white,
                    height: 1,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
