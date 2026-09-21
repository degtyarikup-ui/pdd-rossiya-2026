import 'package:flutter/material.dart';
import 'package:pdd_app/core/constants/app_colors.dart';
import 'package:pdd_app/l10n/l10n.dart';

/// Hidden extra (long-press on the garage button): forces the weather and
/// the season, or returns them to automatic.
class GameDebugSheet extends StatefulWidget {
  final String? weatherOverride;
  final String? seasonOverride;
  final ValueChanged<String?> onWeatherChanged;
  final ValueChanged<String?> onSeasonChanged;

  const GameDebugSheet({
    super.key,
    required this.weatherOverride,
    required this.seasonOverride,
    required this.onWeatherChanged,
    required this.onSeasonChanged,
  });

  @override
  State<GameDebugSheet> createState() => _GameDebugSheetState();
}

class _GameDebugSheetState extends State<GameDebugSheet> {
  late String? _weather = widget.weatherOverride;
  late String? _season = widget.seasonOverride;

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
