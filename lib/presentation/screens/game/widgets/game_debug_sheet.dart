import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Hidden extra (long-press on the garage button): forces the weather and
/// the season, or returns them to automatic.
class GameDebugSheet extends StatefulWidget {
  final String? weatherOverride;
  final String? seasonOverride;
  final bool unlimitedFuel;
  final ValueChanged<String?> onWeatherChanged;
  final ValueChanged<String?> onSeasonChanged;
  final ValueChanged<bool> onUnlimitedFuelChanged;
  final String? qualityTier;
  final ValueChanged<String?> onQualityTierChanged;
  final bool perfHud;
  final ValueChanged<bool> onPerfHudChanged;

  static void _ignore(bool _) {}
  static void _ignoreTier(String? _) {}

  const GameDebugSheet({
    super.key,
    required this.weatherOverride,
    required this.seasonOverride,
    required this.unlimitedFuel,
    required this.onWeatherChanged,
    required this.onSeasonChanged,
    required this.onUnlimitedFuelChanged,
    this.qualityTier,
    this.onQualityTierChanged = _ignoreTier,
    this.perfHud = false,
    this.onPerfHudChanged = _ignore,
  });

  @override
  State<GameDebugSheet> createState() => _GameDebugSheetState();
}

class _GameDebugSheetState extends State<GameDebugSheet> {
  late String? _weather = widget.weatherOverride;
  late String? _season = widget.seasonOverride;
  late bool _unlimitedFuel = widget.unlimitedFuel;
  late bool _perfHud = widget.perfHud;
  late String? _tier = widget.qualityTier;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final weather = [
      (null, appL10n.gameSceneAuto),
      ('clear', appL10n.gameSceneClear),
      ('overcast', appL10n.gameSceneOvercast),
      ('rain', appL10n.gameScenePrecip),
    ];
    final seasons = [
      (null, appL10n.gameSceneCalendar),
      ('summer', appL10n.gameSceneSummer),
      ('autumn', appL10n.gameSceneAutumn),
      ('winter', appL10n.gameSceneWinter),
    ];
    Widget title(String text) => Text(
      text,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: colors.primaryText,
      ),
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _unlimitedFuel,
              secondary: Icon(
                Icons.all_inclusive_rounded,
                color: _unlimitedFuel ? colors.gold : colors.secondaryText,
              ),
              title: Text(
                appL10n.gameDebugUnlimitedFuel,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
              ),
              subtitle: Text(
                appL10n.gameDebugUnlimitedFuelHint,
                style: TextStyle(color: colors.secondaryText),
              ),
              onChanged: (value) {
                setState(() => _unlimitedFuel = value);
                widget.onUnlimitedFuelChanged(value);
              },
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _perfHud,
              secondary: Icon(
                Icons.speed_rounded,
                color: _perfHud ? colors.accent : colors.secondaryText,
              ),
              title: Text(
                appL10n.gameDebugPerf,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
              ),
              subtitle: Text(
                appL10n.gameDebugPerfHint,
                style: TextStyle(color: colors.secondaryText),
              ),
              onChanged: (value) {
                setState(() => _perfHud = value);
                widget.onPerfHudChanged(value);
              },
            ),
            const SizedBox(height: 12),
            title(appL10n.gameDebugTier),
            const SizedBox(height: 4),
            Text(
              appL10n.gameDebugTierHint,
              style: TextStyle(fontSize: 12, color: colors.secondaryText),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final (value, label) in [
                  (null, appL10n.gameSceneAuto),
                  ('low', appL10n.gameDebugTierLow),
                  ('mid', appL10n.gameDebugTierMid),
                  ('high', appL10n.gameDebugTierHigh),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _tier == value,
                    onSelected: (_) {
                      setState(() => _tier = value);
                      widget.onQualityTierChanged(value);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            title(appL10n.gameSceneWeather),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final (value, label) in weather)
                  ChoiceChip(
                    label: Text(label),
                    selected: _weather == value,
                    onSelected: (_) {
                      setState(() => _weather = value);
                      widget.onWeatherChanged(value);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            title(appL10n.gameSceneSeason),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final (value, label) in seasons)
                  ChoiceChip(
                    label: Text(label),
                    selected: _season == value,
                    onSelected: (_) {
                      setState(() => _season = value);
                      widget.onSeasonChanged(value);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
