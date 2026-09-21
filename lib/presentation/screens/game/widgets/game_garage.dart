import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
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
  late final List<GameCar> _items = [
    ...widget.cars,
    if (widget.premium)
      const GameCar(GameGarageService.cyber, GameGarageService.cyberPaint),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    appL10n.gameGarage,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: colors.primaryText,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
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
                itemCount: _items.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: MediaQuery.sizeOf(context).width >= 600
                      ? 4
                      : 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.1,
                ),
                itemBuilder: (context, i) {
                  final car = _items[i];
                  final isSelected = car.key == widget.selected.key;
                  final isCyber = car.id == GameGarageService.cyber;
                  final label =
                      '${gameCarName(car.id)}, ${gamePaintName(car.paint)}';
                  return Semantics(
                    selected: isSelected,
                    button: true,
                    label: label,
                    child: Material(
                      color: isSelected
                          ? colors.accentSurface10
                          : colors.cardBackground,
                      borderRadius: BorderRadius.circular(18),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => Navigator.pop(context, car),
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
                                  Container(
                                    width: 12,
                                    height: 12,
                                    margin: const EdgeInsets.only(right: 6),
                                    decoration: BoxDecoration(
                                      color: gamePaintColors[car.paint],
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  Flexible(
                                    child: Text(
                                      gameCarName(car.id),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isCyber
                                            ? colors.gold
                                            : colors.primaryText,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
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

  Future<void> _load() async {
    try {
      final url = await widget.loader!(widget.car.id, widget.car.paint);
      final comma = url.indexOf(',');
      if (comma < 0) return;
      final bytes = base64Decode(url.substring(comma + 1));
      widget.cache[widget.car.key] = bytes;
      if (mounted) setState(() => _bytes = bytes);
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
    if (const ['hatch', 'sedan', 'suv', 'pickup'].contains(id)) {
      return Image.asset(
        'assets/game/vehicle-$id.png',
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      );
    }
    return Icon(
      Icons.directions_car_rounded,
      size: 56,
      color: gamePaintColors[widget.car.paint],
    );
  }
}
