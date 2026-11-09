import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdd_app/core/constants/app_dimensions.dart';
import 'package:pdd_app/presentation/widgets/app_chrome_icon_button.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/services/game_garage_service.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Every model the engine can build (used to validate ids from the bridge).
String gameCarName(String id) => switch (id) {
  'sedan' => appL10n.gameCarSedan,
  'coupe' => appL10n.gameCarCoupe,
  'wagon' => appL10n.gameCarWagon,
  'suv' => appL10n.gameCarSuv,
  'pickup' => appL10n.gameCarPickup,
  'cyber' => appL10n.gameCarCyber,
  _ => appL10n.gameCarHatch,
};

String gamePaintName(String paint) =>
    switch (GameGarageService.normalizePaint(paint)) {
      'blue' => appL10n.gamePaintBlue,
      'green' => appL10n.gamePaintGreen,
      'white' => appL10n.gamePaintWhite,
      'black' => appL10n.gamePaintBlack,
      'yellow' => appL10n.gamePaintYellow,
      _ => appL10n.gamePaintRed,
    };

/// One palette shared by the garage, game bridge, and ownership service.
final gamePaintColors = {
  for (final entry in GameGarageService.paintHex.entries)
    entry.key: Color(entry.value),
};

String gameRewardName(GameGarageReward reward) => reward.isModel
    ? appL10n.gameAchievementModel(gameCarName(reward.model!))
    : appL10n.gameAchievementPaint(gamePaintName(reward.paint!));

double gameAchievementFraction(GameGarageService garage) {
  final next = garage.nextReward;
  if (next == null) return 1;
  var previous = 0;
  for (final reward in GameGarageService.rewards) {
    if (reward.threshold >= next.threshold) break;
    previous = reward.threshold;
  }
  return ((garage.correctTotal - previous) / (next.threshold - previous))
      .clamp(0, 1)
      .toDouble();
}

/// Renders a car preview through the engine;
/// returns a PNG data URL or an empty string.
typedef GameThumbnailLoader = Future<String> Function(String id, String paint);

/// The collection and paint picker use the same catalogue as the Godot launch.
class GameGarage extends StatefulWidget {
  const GameGarage({
    super.key,
    required this.selected,
    required this.models,
    required this.paints,
    required this.correctTotal,
    required this.mileageMm,
    required this.onSelect,
  });

  final GameCar selected;
  final List<String> models, paints;
  final int correctTotal;
  final Map<String, int> mileageMm;
  final Future<bool> Function(GameCar) onSelect;

  @override
  State<GameGarage> createState() => _GameGarageState();
}

class _GameGarageState extends State<GameGarage> {
  late GameCar _selected = widget.selected;

  Future<void> _openCar(String id) async {
    HapticFeedbackHelper.select();
    final selected = await Navigator.of(context).push<GameCar>(
      MaterialPageRoute(
        builder: (_) => _GarageCarDetail(
          car: GameCar(id, _selected.paint),
          unlocked: widget.models.contains(id),
          paints: widget.paints,
          correctTotal: widget.correctTotal,
          mileageMm: widget.mileageMm[id] ?? 0,
          onSelect: widget.onSelect,
        ),
      ),
    );
    if (mounted && selected != null) setState(() => _selected = selected);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    // Show earned models in their unlock order, with the Premium model last.
    final ids = [
      GameGarageService.starter.id,
      for (final reward in GameGarageService.rewards)
        if (reward.model != null) reward.model!,
      GameGarageService.cyber,
    ];
    return _GaragePage(
      title: appL10n.gamesGarageTitle,
      children: [
        Text(
          appL10n.gamesGarageCollection(widget.models.length, ids.length),
          style: TextStyle(color: colors.secondaryText, fontSize: 14),
        ),
        const SizedBox(height: AppDimensions.spacingL),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = AppDimensions.spacingM;
            final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
            final minimumWidth = 144 * scale.clamp(1.0, 1.65);
            final columns =
                ((constraints.maxWidth + gap) / (minimumWidth + gap))
                    .floor()
                    .clamp(1, 3);
            final width =
                (constraints.maxWidth - (columns - 1) * gap) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final id in ids)
                  SizedBox(
                    width: width,
                    child: _GarageCarCard(
                      car: GameCar(id, _selected.paint),
                      unlocked: widget.models.contains(id),
                      selected: id == _selected.id,
                      correctTotal: widget.correctTotal,
                      mileageMm: widget.mileageMm[id] ?? 0,
                      onTap: () => _openCar(id),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _GaragePage extends StatelessWidget {
  const _GaragePage({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.all(AppDimensions.screenPadding),
              children: [
                Row(
                  children: [
                    Tooltip(
                      message: appL10n.back,
                      child: AppChromeIconButton(
                        icon: Icons.arrow_back_rounded,
                        onTap: () => Navigator.maybePop(context),
                      ),
                    ),
                    const SizedBox(width: AppDimensions.spacingM),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: colors.primaryText,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppDimensions.spacingL),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

GameGarageReward? _modelReward(String id) {
  for (final reward in GameGarageService.rewards) {
    if (reward.model == id) return reward;
  }
  return null;
}

String _odometer(BuildContext context, int millimeters) {
  final format = NumberFormat.decimalPattern(
    Localizations.localeOf(context).toLanguageTag(),
  )..maximumFractionDigits = 3;
  final km = millimeters / 1000000;
  return '${millimeters > 0 && millimeters < 1000 ? '<${format.format(.001)}' : format.format(km)} ${appL10n.gameKilometers}';
}

class _GarageCarCard extends StatelessWidget {
  const _GarageCarCard({
    required this.car,
    required this.unlocked,
    required this.selected,
    required this.correctTotal,
    required this.mileageMm,
    required this.onTap,
  });

  final GameCar car;
  final bool unlocked, selected;
  final int correctTotal, mileageMm;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final reward = _modelReward(car.id);
    final name = gameCarName(car.id);
    final detail = unlocked
        ? _odometer(context, mileageMm)
        : reward == null
        ? appL10n.gamesPremiumBadge
        : appL10n.gameAchievementCount(
            correctTotal.clamp(0, reward.threshold),
            reward.threshold,
          );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
      side: BorderSide(color: selected ? colors.accent : colors.divider),
    );
    return Semantics(
      button: true,
      onTap: onTap,
      selected: selected,
      label: unlocked
          ? '$name, ${appL10n.gamesGarageOdometer(detail)}'
          : '$name, ${appL10n.gamesGarageLocked}, $detail',
      child: Material(
        color: colors.cardBackground,
        clipBehavior: Clip.antiAlias,
        shape: shape,
        child: InkWell(
          onTap: onTap,
          excludeFromSemantics: true,
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 1.65,
                  child: _GarageCarArt(
                    car: car,
                    locked: !unlocked,
                    selected: selected,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppDimensions.spacingM),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color: colors.primaryText,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        detail,
                        style: TextStyle(
                          color: colors.secondaryText,
                          fontSize: 13,
                        ),
                      ),
                    ],
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

class _GarageCarArt extends StatelessWidget {
  const _GarageCarArt({
    required this.car,
    this.locked = false,
    this.selected = false,
  });

  final GameCar car;
  final bool locked, selected;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final tint = gamePaintColors[car.paint]!;
    final picture = Image.asset(
      'assets/game/garage/${car.id}-${locked ? 'red' : car.paint}.webp',
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      gaplessPlayback: true,
      color: locked ? AppColors.black : null,
      colorBlendMode: BlendMode.srcIn,
    );
    return Ink(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: locked
              ? const [Color(0xFF858E9A), Color(0xFF525C6B)]
              : [
                  Color.alphaBlend(
                    tint.withValues(alpha: .24),
                    colors.cardBackground,
                  ),
                  Color.alphaBlend(
                    colors.accent.withValues(alpha: .09),
                    colors.cardBackground,
                  ),
                ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          picture,
          if (locked || selected)
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: locked ? const Color(0xFF29313C) : colors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      locked ? Icons.lock_rounded : Icons.check_rounded,
                      size: 15,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GarageCarDetail extends StatefulWidget {
  const _GarageCarDetail({
    required this.car,
    required this.unlocked,
    required this.paints,
    required this.correctTotal,
    required this.mileageMm,
    required this.onSelect,
  });

  final GameCar car;
  final bool unlocked;
  final List<String> paints;
  final int correctTotal, mileageMm;
  final Future<bool> Function(GameCar) onSelect;

  @override
  State<_GarageCarDetail> createState() => _GarageCarDetailState();
}

class _GarageCarDetailState extends State<_GarageCarDetail> {
  late String _paint = widget.car.paint;
  bool _saving = false;

  Future<void> _select(GameCar car) async {
    if (_saving) return;
    setState(() => _saving = true);
    final saved = await widget.onSelect(car);
    if (!mounted) return;
    if (saved) {
      HapticFeedbackHelper.confirm();
      Navigator.pop(context, car);
    } else {
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(appL10n.gamesGarageSaveFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final car = GameCar(widget.car.id, _paint);
    final reward = _modelReward(car.id);
    return PopScope(
      canPop: !_saving,
      child: _GaragePage(
        title: gameCarName(car.id),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
            child: SizedBox(
              height: 200,
              child: Material(
                child: _GarageCarArt(car: car, locked: !widget.unlocked),
              ),
            ),
          ),
          const SizedBox(height: AppDimensions.spacingL),
          if (widget.unlocked) ...[
            Text(
              appL10n.gamesGarageOdometer(_odometer(context, widget.mileageMm)),
              style: TextStyle(color: colors.secondaryText, fontSize: 14),
            ),
            const SizedBox(height: AppDimensions.spacingL),
            Text(
              appL10n.gamesGaragePaint(gamePaintName(_paint)),
              style: TextStyle(
                color: colors.primaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingS),
            Wrap(
              spacing: AppDimensions.spacingS,
              runSpacing: AppDimensions.spacingS,
              children: [
                for (final paint in widget.paints)
                  Semantics(
                    selected: paint == _paint,
                    child: Tooltip(
                      message: gamePaintName(paint),
                      child: IconButton(
                        onPressed: _saving
                            ? null
                            : () {
                                HapticFeedbackHelper.select();
                                setState(() => _paint = paint);
                              },
                        style: IconButton.styleFrom(
                          backgroundColor: gamePaintColors[paint],
                          foregroundColor:
                              ThemeData.estimateBrightnessForColor(
                                    gamePaintColors[paint]!,
                                  ) ==
                                  Brightness.dark
                              ? AppColors.white
                              : AppColors.black,
                          side: BorderSide(
                            color: paint == _paint
                                ? colors.accent
                                : colors.divider,
                          ),
                          minimumSize: const Size.square(48),
                        ),
                        icon: Icon(
                          Icons.check_rounded,
                          color: paint == _paint ? null : Colors.transparent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingS),
            Text(
              appL10n.gamePaintAllCars,
              style: TextStyle(color: colors.secondaryText),
            ),
            const SizedBox(height: AppDimensions.spacingL),
            FilledButton(
              onPressed: _saving ? null : () => _select(car),
              child: Text(appL10n.gameRevealChoose),
            ),
          ] else if (reward == null)
            Text(appL10n.gameGaragePremiumCar)
          else ...[
            Text(appL10n.gamesGarageUnlockInCity),
            const SizedBox(height: AppDimensions.spacingS),
            Text(
              appL10n.gameAchievementCount(
                widget.correctTotal.clamp(0, reward.threshold),
                reward.threshold,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingS),
            LinearProgressIndicator(
              value: (widget.correctTotal / reward.threshold).clamp(0, 1),
            ),
          ],
        ],
      ),
    );
  }
}

/// A car picture from the engine, cached per model+paint; falls back to the
/// bundled PNG of the model (or a car icon) while it loads or without a
/// renderer.
class GameCarThumbnail extends StatefulWidget {
  final GameCar car;
  final GameThumbnailLoader? loader;
  final Map<String, Uint8List> cache;

  const GameCarThumbnail({
    super.key,
    required this.car,
    required this.loader,
    required this.cache,
  });

  @override
  State<GameCarThumbnail> createState() => _GameCarThumbnailState();
}

class _GameCarThumbnailState extends State<GameCarThumbnail> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = widget.cache[widget.car.key];
    if (_bytes == null && widget.loader != null) _load();
  }

  @override
  void didUpdateWidget(GameCarThumbnail old) {
    super.didUpdateWidget(old);
    // Same element, another car (e.g. the HUD button after a pick): drop the
    // old picture instead of showing it until something else rebuilds.
    if (old.car.key != widget.car.key) {
      _bytes = widget.cache[widget.car.key];
      _attempts = 0;
      if (_bytes == null && widget.loader != null) _load();
    }
  }

  int _attempts = 0;
  Timer? _retry;

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final car = widget.car;
    try {
      final url = await widget.loader!(car.id, car.paint);
      final comma = url.indexOf(',');
      if (comma < 0) {
        // The engine is still loading: ask again shortly, so the real car in
        // its real paint replaces the bundled picture as soon as it can.
        if (_attempts++ < 30) {
          _retry?.cancel();
          _retry = Timer(const Duration(seconds: 1), () {
            if (mounted && widget.car.key == car.key && _bytes == null) {
              _load();
            }
          });
        }
        return;
      }
      final bytes = base64Decode(url.substring(comma + 1));
      widget.cache[car.key] = bytes;
      // A slower render of a previous car must not overwrite the current one.
      if (mounted && widget.car.key == car.key) setState(() => _bytes = bytes);
    } catch (_) {
      /* Keep the fallback picture. */
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes != null) {
      return Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true);
    }
    final id = widget.car.id;
    // Every model has a bundled picture of the same mesh (default paint):
    // never an icon in place of the car.
    if (GameGarageService.vehicleIds.contains(id)) {
      return Image.asset(
        'assets/game/vehicle-$id.png',
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      );
    }
    return const SizedBox.shrink();
  }
}
