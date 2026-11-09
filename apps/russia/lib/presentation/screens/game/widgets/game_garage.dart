import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle, rootBundle;
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
  'mini' => appL10n.gameCarMini,
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
      'pink' => appL10n.gamePaintPink,
      GameGarageService.leopard => appL10n.gamePaintLeopard,
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
    this.modelPaints = const {},
    required this.models,
    required this.paints,
    required this.correctTotal,
    required this.mileageMm,
    required this.onSelect,
  });

  final GameCar selected;
  final Map<String, String> modelPaints;
  final List<String> models, paints;
  final int correctTotal;
  final Map<String, int> mileageMm;
  final Future<bool> Function(GameCar) onSelect;

  @override
  State<GameGarage> createState() => _GameGarageState();
}

enum _GaragePreview { actual, newcomer, premium, earned }

class _GameGarageState extends State<GameGarage> {
  late GameCar _selected = widget.selected;
  late final Map<String, String> _modelPaints = {
    ...widget.modelPaints,
    widget.selected.id: widget.selected.paint,
  };
  final Map<String, String> _previewPaints = {};
  GameCar _previewSelected = GameGarageService.starter;
  _GaragePreview _preview = _GaragePreview.actual;

  bool get _isPreview => _preview != _GaragePreview.actual;
  GameCar get _car => _isPreview ? _previewSelected : _selected;

  GameCar _paintedCar(String id) => GameCar(
    id,
    (_isPreview ? _previewPaints : _modelPaints)[id] ??
        GameGarageService.starter.paint,
  );
  List<String> get _models => switch (_preview) {
    _GaragePreview.actual => widget.models,
    _GaragePreview.newcomer => [GameGarageService.starter.id],
    _GaragePreview.premium => GameGarageService.vehicleIds,
    _GaragePreview.earned => GameGarageService.models,
  };
  List<String> get _paints => switch (_preview) {
    _GaragePreview.actual => widget.paints,
    _GaragePreview.newcomer => [GameGarageService.starter.paint],
    _GaragePreview.premium => GameGarageService.allPaints,
    _GaragePreview.earned => GameGarageService.paints,
  };
  int get _correctTotal => switch (_preview) {
    _GaragePreview.actual => widget.correctTotal,
    _GaragePreview.earned => GameGarageService.rewards.last.threshold,
    _ => 0,
  };

  int _mileageOf(String id) => _isPreview ? 0 : widget.mileageMm[id] ?? 0;

  Future<void> _openCar(String id) async {
    HapticFeedbackHelper.select();
    final previewing = _isPreview;
    final selected = await Navigator.of(context).push<GameCar>(
      MaterialPageRoute(
        builder: (_) => _GarageCarDetail(
          car: _paintedCar(id),
          unlocked: _models.contains(id),
          paints: _paints,
          correctTotal: _correctTotal,
          mileageMm: _mileageOf(id),
          onSelect: previewing ? (_) async => true : widget.onSelect,
        ),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      if (previewing) {
        _previewSelected = selected;
        _previewPaints[selected.id] = selected.paint;
      } else {
        _selected = selected;
        _modelPaints[selected.id] = selected.paint;
      }
    });
  }

  Widget _previewMenu() {
    final options = {
      _GaragePreview.actual: appL10n.gamesGaragePreviewActual,
      _GaragePreview.newcomer: appL10n.gamesGaragePreviewNew,
      _GaragePreview.premium: appL10n.gamesPremiumBadge,
      _GaragePreview.earned: appL10n.gamesGaragePreviewEarned,
    };
    final colors = AppColors.of(context);
    return PopupMenuButton<_GaragePreview>(
      key: const ValueKey('garage-preview-menu'),
      tooltip: appL10n.gamesGaragePreview,
      icon: Icon(Icons.tune_rounded, color: _isPreview ? colors.accent : null),
      onSelected: (value) => setState(() {
        _preview = value;
        _previewSelected = GameGarageService.starter;
        _previewPaints.clear();
      }),
      itemBuilder: (_) => [
        for (final option in options.entries)
          CheckedPopupMenuItem(
            value: option.key,
            checked: _preview == option.key,
            child: Text(option.value),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          enabled: false,
          child: Text(
            appL10n.gamesGarageDebugAnswers(widget.correctTotal),
            style: TextStyle(color: colors.secondaryText, fontSize: 12),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Ordinary models appear in unlock order, followed by the Premium pair.
    final ids = [
      GameGarageService.starter.id,
      for (final reward in GameGarageService.rewards)
        if (reward.model != null) reward.model!,
      ...GameGarageService.premiumModels,
    ];
    final owned = _models;
    return _GaragePage(
      title: appL10n.gamesGarageTitle,
      action: const bool.fromEnvironment('GAME_DEBUG') ? _previewMenu() : null,
      children: [
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
                    height: width * .86,
                    child: _GarageCarCard(
                      key: ValueKey('garage-car-$id'),
                      car: _paintedCar(id),
                      unlocked: owned.contains(id),
                      selected: id == _car.id,
                      correctTotal: _correctTotal,
                      mileageMm: _mileageOf(id),
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
  const _GaragePage({required this.title, required this.children, this.action});

  final String title;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.screenPadding,
                AppDimensions.screenPadding,
                AppDimensions.screenPadding,
                0,
              ),
              child: Column(
                children: [
                  _GarageHeader(title: title, action: action),
                  const SizedBox(height: AppDimensions.spacingL),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(
                        bottom: AppDimensions.screenPadding,
                      ),
                      children: children,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GarageHeader extends StatelessWidget {
  const _GarageHeader({
    required this.title,
    this.action,
    this.onArtwork = false,
  });

  final String title;
  final Widget? action;
  final bool onArtwork;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final ink = onArtwork ? AppColors.white : colors.primaryText;
    return Row(
      children: [
        Tooltip(
          message: appL10n.back,
          child: AppChromeIconButton(
            icon: Icons.arrow_back_rounded,
            onTap: () => Navigator.maybePop(context),
            backgroundColor: onArtwork ? _GarageBadge.background : null,
            iconColor: ink,
          ),
        ),
        const SizedBox(width: AppDimensions.spacingM),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: ink,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: AppDimensions.spacingS),
          action!,
        ],
      ],
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

class _GarageBadge extends StatelessWidget {
  const _GarageBadge(this.label, {this.premium = false}) : outlined = true;
  const _GarageBadge.mileage(this.label) : premium = false, outlined = false;

  static const background = Color(0xD9162034);
  static const premiumInk = Color(0xFF352005);

  final String label;
  final bool premium, outlined;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: premium ? AppColors.of(context).gold : background,
      borderRadius: BorderRadius.circular(7),
      border: outlined ? Border.all(color: const Color(0x35FFFFFF)) : null,
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        label,
        style: TextStyle(
          color: premium ? premiumInk : AppColors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ),
  );
}

class _GarageCarCard extends StatelessWidget {
  const _GarageCarCard({
    super.key,
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
    final reward = _modelReward(car.id);
    final name = gameCarName(car.id);
    final premium = !unlocked && reward == null;
    final badgeColor = premium
        ? AppColors.of(context).gold
        : _GarageBadge.background;
    final detail = unlocked
        ? _odometer(context, mileageMm)
        : reward == null
        ? appL10n.gamesPremiumBadge
        : appL10n.gameAchievementCount(
            correctTotal.clamp(0, reward.threshold),
            reward.threshold,
          );
    return Semantics(
      button: true,
      onTap: onTap,
      selected: selected,
      label: unlocked
          ? '$name, ${appL10n.gamesGarageOdometer(detail)}'
          : '$name, ${appL10n.gamesGarageLocked}, $detail',
      child: Material(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.cardRadius),
          side: BorderSide(
            color: selected ? AppColors.accent : const Color(0x44FFFFFF),
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          excludeFromSemantics: true,
          child: ExcludeSemantics(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _GarageCarArt(car: car, locked: !unlocked),
                Positioned(
                  left: 9,
                  right: 9,
                  top: 9,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: unlocked
                              ? _GarageBadge.mileage(detail)
                              : _GarageBadge(detail, premium: premium),
                        ),
                      ),
                      if (!unlocked || selected) ...[
                        const SizedBox(width: 6),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: selected ? AppColors.accent : badgeColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0x35FFFFFF)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              selected
                                  ? Icons.check_rounded
                                  : Icons.lock_rounded,
                              color: premium
                                  ? _GarageBadge.premiumInk
                                  : AppColors.white,
                              size: 15,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 10,
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.12,
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
}

enum _GarageLivery {
  hatch(0xFFFF7C58, 0xFFB13624),
  sedan(0xFF588CFD, 0xFF1C4C9F),
  wagon(0xFF91C752, 0xFF386419),
  coupe(0xFFAE78F8, 0xFF63399E),
  suv(0xFFFFBF56, 0xFF9B520E),
  pickup(0xFF41CEBD, 0xFF0D736A),
  mini(0xFFFA80BD, 0xFF9B3069),
  cyber(0xFF90A8CF, 0xFF375477);

  const _GarageLivery(this.light, this.dark);

  final int light, dark;
}

class _GarageCarArt extends StatelessWidget {
  const _GarageCarArt({required this.car, this.locked = false});

  final GameCar car;
  final bool locked;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      _GarageBackdrop(car: car, locked: locked),
      Center(
        child: FractionallySizedBox(
          widthFactor: 1,
          heightFactor: .82,
          child: _GarageCarImage(car: car, locked: locked),
        ),
      ),
    ],
  );
}

class _GarageBackdrop extends StatelessWidget {
  const _GarageBackdrop({
    super.key,
    required this.car,
    required this.locked,
    this.fullScreen = false,
  });

  final GameCar car;
  final bool locked, fullScreen;

  @override
  Widget build(BuildContext context) {
    final livery = _GarageLivery.values.byName(car.id);
    final colors = AppColors.of(context);
    final paint = gamePaintColors[car.paint]!;
    final tint = Color.lerp(paint, AppColors.white, .24)!;
    Color surface(Color color) =>
        fullScreen ? Color.lerp(color, const Color(0xFF151A29), .44)! : color;
    return Stack(
      fit: StackFit.expand,
      children: [
        Ink(
          decoration: BoxDecoration(
            color: locked
                ? surface(
                    Color.lerp(
                      colors.cardBackground,
                      colors.secondaryText,
                      .28,
                    )!,
                  )
                : null,
            gradient: locked
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      surface(Color.lerp(Color(livery.light), tint, .64)!),
                      surface(Color.lerp(Color(livery.dark), paint, .45)!),
                    ],
                  ),
          ),
        ),
        if (!locked)
          CustomPaint(painter: _GaragePattern(livery, cover: fullScreen)),
      ],
    );
  }
}

class _GarageCarImage extends StatelessWidget {
  const _GarageCarImage({required this.car, required this.locked});

  final GameCar car;
  final bool locked;

  @override
  Widget build(BuildContext context) => Image.asset(
    _garagePreviewAsset(car.id, locked ? 'red' : car.paint),
    fit: BoxFit.contain,
    excludeFromSemantics: true,
    gaplessPlayback: true,
    color: locked ? AppColors.black : null,
    colorBlendMode: BlendMode.srcIn,
  );
}

String _garagePreviewAsset(String id, String paint) =>
    'assets/game/garage/$id-$paint.webp';

/// A packed set of studio renders from render_garage.gd. Decode only the
/// visible car's paint and keep its viewing angle while the paint changes.
class _GarageTurntable extends StatefulWidget {
  const _GarageTurntable({super.key, required this.car, required this.locked});

  final GameCar car;
  final bool locked;

  @override
  State<_GarageTurntable> createState() => _GarageTurntableState();
}

class _GarageTurntableState extends State<_GarageTurntable> {
  static const _frameCount = _TurntableFrame.grid * _TurntableFrame.grid;

  ui.Image? _atlas;
  String? _atlasKey;
  bool _loading = false;
  double _angle = 0;

  int get _frame => _angle.round() % _frameCount;
  String get _key =>
      '${widget.car.id}-${widget.locked ? 'red' : widget.car.paint}';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(_GarageTurntable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.car.key != widget.car.key ||
        oldWidget.locked != widget.locked) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _atlas?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final key = _key;
    if (_loading || _atlasKey == key) return;
    _loading = true;
    try {
      final data = await rootBundle.load(
        'assets/game/garage_turntable/$key.webp',
      );
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      try {
        final atlas = (await codec.getNextFrame()).image;
        if (mounted && _key == key) {
          final previous = _atlas;
          setState(() {
            _atlas = atlas;
            _atlasKey = key;
          });
          previous?.dispose();
        } else {
          atlas.dispose();
        }
      } finally {
        codec.dispose();
      }
    } catch (_) {
      // The small catalog art remains available if the atlas cannot be loaded.
      if (mounted && _key == key && _atlas != null) {
        final previous = _atlas;
        setState(() {
          _atlas = null;
          _atlasKey = null;
        });
        previous?.dispose();
      }
    } finally {
      _loading = false;
      if (mounted && _key != key) unawaited(_load());
    }
  }

  void _rotateBy(double frames) {
    final previous = _frame;
    _angle = (_angle + frames) % _frameCount;
    if (_frame != previous) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final atlas = _atlas;
    final artwork = AspectRatio(
      aspectRatio: 960 / 528,
      child: atlas == null
          ? _GarageCarImage(car: widget.car, locked: widget.locked)
          : CustomPaint(painter: _TurntableFrame(atlas, _frame, widget.locked)),
    );
    if (widget.locked) return artwork;
    return Semantics(
      label: appL10n.gamesGarageRotateCar,
      onIncrease: () => _rotateBy(1),
      onDecrease: () => _rotateBy(-1),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) {
            final width = context.size!.width;
            _rotateBy(-details.delta.dx * _frameCount / width);
          },
          child: RepaintBoundary(child: artwork),
        ),
      ),
    );
  }
}

class _TurntableFrame extends CustomPainter {
  const _TurntableFrame(this.atlas, this.frame, this.locked);

  // Keep the atlas grid in sync with render_garage.gd.
  static const grid = 4;

  final ui.Image atlas;
  final int frame;
  final bool locked;

  @override
  void paint(Canvas canvas, Size size) {
    final width = atlas.width / grid;
    final height = atlas.height / grid;
    canvas.drawImageRect(
      atlas,
      Rect.fromLTWH(
        (frame % grid) * width,
        (frame ~/ grid) * height,
        width,
        height,
      ),
      Offset.zero & size,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..colorFilter = locked
            ? const ColorFilter.mode(AppColors.black, BlendMode.srcIn)
            : null,
    );
  }

  @override
  bool shouldRepaint(covariant _TurntableFrame oldDelegate) =>
      oldDelegate.atlas != atlas ||
      oldDelegate.frame != frame ||
      oldDelegate.locked != locked;
}

class _GaragePattern extends CustomPainter {
  const _GaragePattern(this.livery, {required this.cover});

  final _GarageLivery livery;
  final bool cover;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final scaleX = size.width / 160;
    final scaleY = size.height / 136;
    if (cover) {
      final scale = math.max(scaleX, scaleY);
      canvas.translate(
        (size.width - 160 * scale) / 2,
        (size.height - 136 * scale) / 2,
      );
      canvas.scale(scale);
    } else {
      canvas.scale(scaleX, scaleY);
    }
    final light = Paint()..color = const Color(0x2AFFF7DF);
    final dark = Paint()..color = const Color(0x180B1020);
    final stroke = Paint()
      ..color = const Color(0x3AFFF7DF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    switch (livery) {
      case _GarageLivery.hatch:
        for (var x = -108.0; x < 190; x += 30) {
          canvas.drawPath(
            Path()
              ..moveTo(x + 84, 0)
              ..lineTo(x + 99, 0)
              ..lineTo(x + 15, 136)
              ..lineTo(x, 136)
              ..close(),
            x > 50 ? light : dark,
          );
        }
      case _GarageLivery.sedan:
        for (var row = 0; row < 9; row++) {
          for (var column = 0; column < 11; column++) {
            if ((row + column).isEven) {
              canvas.drawRect(
                Rect.fromLTWH(column * 16.0 - 8, row * 16.0, 16, 16),
                row + column < 6 || row + column > 12 ? light : dark,
              );
            }
          }
        }
      case _GarageLivery.wagon:
        for (var x = -120.0; x < 160; x += 19) {
          canvas.drawPath(
            Path()
              ..moveTo(x, 0)
              ..lineTo(x + 73, 69)
              ..lineTo(x + 152, 69)
              ..lineTo(x + 223, 136),
            stroke,
          );
        }
      case _GarageLivery.coupe:
        const center = Offset(79, 80);
        for (var i = 0; i < 14; i++) {
          final angle = i * math.pi / 7;
          canvas.drawPath(
            Path()
              ..moveTo(center.dx, center.dy)
              ..lineTo(
                center.dx + 170 * math.cos(angle),
                center.dy + 170 * math.sin(angle),
              )
              ..lineTo(
                center.dx + 170 * math.cos(angle + .19),
                center.dy + 170 * math.sin(angle + .19),
              )
              ..close(),
            i.isEven ? light : dark,
          );
        }
      case _GarageLivery.suv:
        for (var r = 12.0; r < 180; r += 12) {
          canvas.drawPath(
            Path()
              ..moveTo(126 - r, 43)
              ..cubicTo(123 - r, 42 - r, 132 + r, 33 - r, 127 + r, 43)
              ..cubicTo(128 + r, 58 + r, 100 - r * .8, 28 + r, 126 - r, 43)
              ..close(),
            stroke,
          );
        }
      case _GarageLivery.pickup:
        for (var row = 0; row < 8; row++) {
          for (var column = 0; column < 8; column++) {
            final x = column * 24.0 + (row.isEven ? -5 : 7);
            final y = row * 20.0;
            final hexagon = Path()..moveTo(x, y - 12);
            for (var point = 1; point < 6; point++) {
              final angle = point * math.pi / 3;
              hexagon.lineTo(
                x + 12 * math.sin(angle),
                y - 12 * math.cos(angle),
              );
            }
            canvas.drawPath(hexagon..close(), column.isEven ? light : dark);
          }
        }
      case _GarageLivery.mini:
        for (var row = 0; row < 8; row++) {
          for (var column = 0; column < 9; column++) {
            final dot = Offset(
              column * 20.0 + (row.isEven ? 0 : 10),
              row * 18.0,
            );
            canvas.drawCircle(dot, (row + column) % 3 == 0 ? 4.8 : 2.4, light);
          }
        }
      case _GarageLivery.cyber:
        for (var y = 8.0; y < 151; y += 13) {
          final x = 35 + (y % 35);
          canvas.drawPath(
            Path()
              ..moveTo(-10, y)
              ..lineTo(x, y)
              ..lineTo(x + 33, y - 33)
              ..lineTo(156, y - 33),
            stroke,
          );
          canvas.drawCircle(Offset(x, y), 2.5, light);
          canvas.drawCircle(Offset(156, y - 33), 2.5, light);
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GaragePattern oldDelegate) =>
      oldDelegate.livery != livery || oldDelegate.cover != cover;
}

class _LeopardSwatch extends CustomPainter {
  const _LeopardSwatch();

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()..color = const Color(0xFF2B1A17);
    for (final (x, y) in const [
      (.27, .28),
      (.69, .24),
      (.52, .48),
      (.27, .69),
      (.74, .68),
    ]) {
      canvas.drawCircle(
        Offset(x * size.width, y * size.height),
        size.width * .09,
        ink,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LeopardSwatch oldDelegate) => false;
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
    final car = GameCar(widget.car.id, _paint);
    final distance = _odometer(context, widget.mileageMm);
    final artwork = Transform.scale(
      scale: 1.18,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: _GarageTurntable(
          key: const ValueKey('garage-turntable'),
          car: car,
          locked: !widget.unlocked,
        ),
      ),
    );
    final controls = widget.unlocked
        ? _GaragePaintPicker(
            selected: _paint,
            available: widget.paints,
            onSelect: _saving
                ? null
                : (paint) {
                    HapticFeedbackHelper.select();
                    setState(() => _paint = paint);
                  },
          )
        : _GarageUnlockHint(
            reward: _modelReward(car.id),
            correctTotal: widget.correctTotal,
          );
    return PopScope(
      canPop: !_saving,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
        ),
        child: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              _GarageBackdrop(
                key: const ValueKey('garage-detail-background'),
                car: car,
                locked: !widget.unlocked,
                fullScreen: true,
              ),
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Padding(
                      padding: const EdgeInsets.all(
                        AppDimensions.screenPadding,
                      ),
                      child: Column(
                        children: [
                          _GarageHeader(
                            title: gameCarName(car.id),
                            onArtwork: true,
                            action: widget.unlocked
                                ? Semantics(
                                    label: appL10n.gamesGarageOdometer(
                                      distance,
                                    ),
                                    excludeSemantics: true,
                                    child: _GarageBadge.mileage(distance),
                                  )
                                : null,
                          ),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                if (constraints.maxHeight < 300 &&
                                    constraints.maxWidth >= 520) {
                                  return Row(
                                    children: [
                                      Expanded(child: Center(child: artwork)),
                                      Expanded(child: Center(child: controls)),
                                    ],
                                  );
                                }
                                return Column(
                                  children: [
                                    Expanded(
                                      child: Align(
                                        alignment: const Alignment(0, .34),
                                        child: artwork,
                                      ),
                                    ),
                                    controls,
                                  ],
                                );
                              },
                            ),
                          ),
                          if (widget.unlocked) ...[
                            const SizedBox(height: AppDimensions.spacingXXXL),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _saving
                                      ? null
                                      : () => _select(car),
                                  child: Text(appL10n.gamesGarageSave),
                                ),
                              ),
                            ),
                          ],
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
    );
  }
}

class _GarageUnlockHint extends StatelessWidget {
  const _GarageUnlockHint({required this.reward, required this.correctTotal});

  final GameGarageReward? reward;
  final int correctTotal;

  @override
  Widget build(BuildContext context) {
    final milestone = reward;
    return DefaultTextStyle.merge(
      style: const TextStyle(
        color: AppColors.white,
        fontWeight: FontWeight.w600,
      ),
      textAlign: TextAlign.center,
      child: milestone == null
          ? Text(appL10n.gameGaragePremiumCar)
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(appL10n.gamesGarageUnlockInCity),
                  const SizedBox(height: AppDimensions.spacingS),
                  Text(
                    appL10n.gameAchievementCount(
                      correctTotal.clamp(0, milestone.threshold),
                      milestone.threshold,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spacingS),
                  LinearProgressIndicator(
                    value: (correctTotal / milestone.threshold).clamp(0, 1),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Keep the swatch geometry, colours and check mark in sync with ride_pause.gd.
class _GaragePaintPicker extends StatelessWidget {
  const _GaragePaintPicker({
    required this.selected,
    required this.available,
    required this.onSelect,
  });

  final String selected;
  final List<String> available;
  final ValueChanged<String>? onSelect;

  @override
  Widget build(BuildContext context) {
    const gap = 12.0;
    const columns = 4;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: columns * 56 + (columns - 1) * gap,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = ((constraints.maxWidth - (columns - 1) * gap) / columns)
              .clamp(40.0, 56.0);
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            alignment: WrapAlignment.center,
            children: [
              for (final paint in GameGarageService.allPaints)
                SizedBox.square(
                  dimension: size,
                  child: _GarageSwatch(
                    paint: paint,
                    selected: paint == selected,
                    locked: !available.contains(paint),
                    onSelect: onSelect == null ? null : () => onSelect!(paint),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _GarageSwatch extends StatelessWidget {
  const _GarageSwatch({
    required this.paint,
    required this.selected,
    required this.locked,
    required this.onSelect,
  });

  final String paint;
  final bool selected, locked;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final color = gamePaintColors[paint]!;
    final luminance = color.computeLuminance();
    final ink = luminance > .5 ? const Color(0xFF121212) : AppColors.white;
    final name = gamePaintName(paint);
    final label = locked ? '$name · ${appL10n.gamesGarageLocked}' : name;
    const outerRadius = BorderRadius.all(Radius.circular(14));
    return Semantics(
      label: label,
      button: true,
      enabled: !locked && onSelect != null,
      selected: selected,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: locked ? null : onSelect,
            borderRadius: outerRadius,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.all(selected ? 4 : 0),
              decoration: BoxDecoration(
                color: colors.cardBackground,
                borderRadius: outerRadius,
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: outerRadius,
                border: Border.all(
                  width: 2,
                  color: selected
                      ? (luminance < .85 ? color : colors.secondaryText)
                      : Colors.transparent,
                ),
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(selected ? 10 : 12),
                  border: luminance > .85
                      ? Border.all(color: colors.divider)
                      : null,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  alignment: Alignment.center,
                  children: [
                    if (paint == GameGarageService.leopard)
                      const CustomPaint(painter: _LeopardSwatch()),
                    if (selected)
                      Icon(Icons.check_rounded, size: 22, color: ink)
                    else if (locked)
                      Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: luminance > .5
                                ? const Color(0xCFFFFFFF)
                                : const Color(0xC91B1A22),
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.lock_rounded,
                              size: 15,
                              color: ink,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
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
    final paint = GameGarageService.normalizePaint(widget.car.paint);
    // Every model has a bundled picture of the same mesh (default paint):
    // never an icon in place of the car.
    if (GameGarageService.vehicleIds.contains(id)) {
      return Image.asset(
        id == GameGarageService.mini ||
                GameGarageService.premiumPaints.contains(paint)
            ? _garagePreviewAsset(id, paint)
            : 'assets/game/vehicle-$id.png',
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      );
    }
    return const SizedBox.shrink();
  }
}
