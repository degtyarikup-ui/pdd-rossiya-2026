import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/core/utils/haptic_feedback.dart';
import 'package:pdd_app/data/services/game_garage_service.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Every model the engine can build (used to validate ids from the bridge).
const gameVehicleIds = [
  'hatch',
  'sedan',
  'coupe',
  'wagon',
  'suv',
  'pickup',
  'cyber',
];

String gameCarName(String id) => switch (id) {
  'sedan' => appL10n.gameCarSedan,
  'coupe' => appL10n.gameCarCoupe,
  'wagon' => appL10n.gameCarWagon,
  'suv' => appL10n.gameCarSuv,
  'pickup' => appL10n.gameCarPickup,
  'cyber' => appL10n.gameCarCyber,
  _ => appL10n.gameCarHatch,
};

String gamePaintName(String paint) => switch (paint) {
  'blue' => appL10n.gamePaintBlue,
  'green' => appL10n.gamePaintGreen,
  'sand' => appL10n.gamePaintSand,
  'white' => appL10n.gamePaintWhite,
  'black' => appL10n.gamePaintBlack,
  'silver' => appL10n.gamePaintSilver,
  'orange' => appL10n.gamePaintOrange,
  'purple' => appL10n.gamePaintPurple,
  'teal' => appL10n.gamePaintTeal,
  'yellow' => appL10n.gamePaintYellow,
  'wine' => appL10n.gamePaintWine,
  'gold' => appL10n.gamePaintGold,
  _ => appL10n.gamePaintRed,
};

/// Swatch colours, mirroring `PDD_VEHICLES.paints` in the engine.
const gamePaintColors = {
  'red': Color(0xFFED4621),
  'blue': Color(0xFF317ED4),
  'green': Color(0xFF4D7768),
  'sand': Color(0xFFD7AA60),
  'white': Color(0xFFF2F3F5),
  'black': Color(0xFF2B2F36),
  'silver': Color(0xFFB9C0C7),
  'orange': Color(0xFFF08A24),
  'purple': Color(0xFF7A5BC6),
  'teal': Color(0xFF2FA3A0),
  'yellow': Color(0xFFE8C547),
  'wine': Color(0xFF8B1E2D),
  'gold': Color(0xFFD4AF37),
};

/// Renders a car preview through the engine (an offscreen three.js frame);
/// returns a PNG data URL or an empty string.
typedef GameThumbnailLoader = Future<String> Function(String id, String paint);

/// The garage sheet: owned cars as engine-rendered thumbnails, the premium
/// cyber truck, and how many correct answers remain until the next car.
class GameGarage extends StatefulWidget {
  final GameCar selected;
  final List<GameCar> cars;
  final bool premium;
  final int correctUntilNext;
  final GameThumbnailLoader? thumbnail;
  final Map<String, Uint8List> thumbnailCache;

  const GameGarage({
    super.key,
    required this.selected,
    required this.cars,
    required this.premium,
    required this.correctUntilNext,
    this.thumbnail,
    this.thumbnailCache = const {},
  });

  @override
  State<GameGarage> createState() => _GameGarageState();
}

class _GameGarageState extends State<GameGarage> {
  /// The model whose colours are being chosen; null shows the model list.
  String? _model;
  late String _paint = widget.selected.paint;

  // Each model's own factory paint, so a premium list is not seven clones.
  static const _defaultPaint = {
    'hatch': 'red',
    'sedan': 'blue',
    'coupe': 'black',
    'wagon': 'green',
    'suv': 'green',
    'pickup': 'sand',
    'cyber': 'gold',
  };

  List<String> get _models => widget.premium
      ? gameVehicleIds
      : [
          for (final id in gameVehicleIds)
            if (widget.cars.any((c) => c.id == id)) id,
        ];

  List<String> _paintsOf(String id) => widget.premium
      ? gamePaintColors.keys.toList()
      : [
          for (final c in widget.cars)
            if (c.id == id) c.paint,
        ];

  /// How a model appears in the list: in the paint being driven, else its
  /// factory paint (premium) or the first paint owned.
  GameCar _listCar(String id) {
    if (widget.selected.id == id) return widget.selected;
    final paints = _paintsOf(id);
    final preferred = _defaultPaint[id];
    return GameCar(id, paints.contains(preferred) ? preferred! : paints.first);
  }

  void _openModel(String id) {
    HapticFeedbackHelper.select();
    final paints = _paintsOf(id);
    // A single colour: nothing to choose — take the car right away.
    if (paints.length == 1) {
      Navigator.pop(context, GameCar(id, paints.single));
      return;
    }
    setState(() {
      _model = id;
      _paint = _listCar(id).paint;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final model = _model;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: model == null
              ? _buildList(colors)
              : _buildColours(colors, model),
        ),
      ),
    );
  }

  Widget _header(AppThemeColors colors, String title, {VoidCallback? onBack}) =>
      Row(
        children: [
          if (onBack != null)
            IconButton(
              tooltip: appL10n.back,
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: colors.primaryText,
              ),
            ),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () {
              HapticFeedbackHelper.tap();
              Navigator.pop(context);
            },
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      );

  Widget _buildList(AppThemeColors colors) {
    final models = _models;
    return Column(
      key: const ValueKey('garage-list'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(colors, appL10n.gameGarage),
        if (!widget.premium)
          Text(
            appL10n.gameGarageNextCar(widget.correctUntilNext),
            style: TextStyle(
              fontFamily: 'Onest',
              fontSize: 13,
              color: colors.secondaryText,
            ),
          ),
        if (!widget.premium) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.workspace_premium_rounded,
                size: 16,
                color: colors.gold,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  appL10n.gameGaragePremiumCar,
                  style: TextStyle(
                    fontFamily: 'Onest',
                    fontSize: 12,
                    color: colors.secondaryText,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Flexible(
          child: GridView.builder(
            shrinkWrap: true,
            itemCount: models.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: MediaQuery.sizeOf(context).width >= 600 ? 4 : 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.1,
            ),
            itemBuilder: (context, i) {
              final car = _listCar(models[i]);
              final isSelected = car.id == widget.selected.id;
              final paints = _paintsOf(car.id).length;
              return Semantics(
                selected: isSelected,
                button: true,
                label: gameCarName(car.id),
                child: Material(
                  color: isSelected
                      ? colors.accentSurface10
                      : colors.cardBackground,
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _openModel(car.id),
                    child: Column(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                            child: GameCarThumbnail(
                              car: car,
                              loader: widget.thumbnail,
                              cache: widget.thumbnailCache,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  gameCarName(car.id),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: car.id == GameGarageService.cyber
                                        ? colors.gold
                                        : colors.primaryText,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              // Several colours: a hint that a choice follows.
                              if (paints > 1) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.palette_outlined,
                                  size: 15,
                                  color: colors.secondaryText,
                                ),
                              ],
                              if (isSelected) ...[
                                const SizedBox(width: 5),
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 18,
                                  color: colors.accent,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildColours(AppThemeColors colors, String model) {
    final paints = _paintsOf(model);
    final car = GameCar(model, _paint);
    return Column(
      key: ValueKey('garage-$model'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(
          colors,
          gameCarName(model),
          onBack: () {
            HapticFeedbackHelper.tap();
            setState(() => _model = null);
          },
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 190,
          child: GameCarThumbnail(
            car: car,
            loader: widget.thumbnail,
            cache: widget.thumbnailCache,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final paint in paints)
              Semantics(
                button: true,
                selected: paint == _paint,
                label: gamePaintName(paint),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedbackHelper.select();
                    setState(() => _paint = paint);
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: gamePaintColors[paint],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: paint == _paint ? colors.accent : colors.divider,
                        width: paint == _paint ? 3 : 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          gamePaintName(_paint),
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Onest', color: colors.secondaryText),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () {
            HapticFeedbackHelper.confirm();
            Navigator.pop(context, car);
          },
          child: Text(appL10n.gameRevealChoose),
        ),
      ],
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

  Future<void> _load() async {
    final car = widget.car;
    try {
      final url = await widget.loader!(car.id, car.paint);
      final comma = url.indexOf(',');
      if (comma < 0) {
        // The engine is still loading: ask again shortly, so the real car in
        // its real paint replaces the bundled picture as soon as it can.
        if (_attempts++ < 30) {
          await Future<void>.delayed(const Duration(seconds: 1));
          if (mounted && widget.car.key == car.key && _bytes == null) {
            await _load();
          }
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
    if (gameVehicleIds.contains(id)) {
      return Image.asset(
        'assets/game/vehicle-$id.png',
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      );
    }
    return const SizedBox.shrink();
  }
}
